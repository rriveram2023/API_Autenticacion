from __future__ import annotations

import os
import socket
from pathlib import Path
from typing import Annotated
from urllib.parse import urlencode

from fastapi import FastAPI, Header, HTTPException, Query, Request, Response
from fastapi.responses import RedirectResponse
from pydantic import BaseModel

from services.auth_api.identity import AuthContext, DirectoryConfig, resolver_contexto_proxy


RUTA_BASE = Path(__file__).resolve().parents[2]
NOMBRE_ENCABEZADO_IDENTIDAD = "X-Authenticated-User"
MODO_AUTENTICACION_PROXY = "proxy_header"


def cargar_variables_entorno_locales() -> None:
    # Permite ejecutar el servicio localmente sin depender de un cargador externo de .env.
    ruta_env = RUTA_BASE / ".env"
    if not ruta_env.exists():
        return

    for linea in ruta_env.read_text(encoding="utf-8").splitlines():
        contenido = linea.strip()
        if not contenido or contenido.startswith("#") or "=" not in contenido:
            continue
        clave, valor = contenido.split("=", 1)
        os.environ.setdefault(clave.strip(), valor.strip().strip('"').strip("'"))


def obtener_configuracion() -> dict[str, str]:
    return {
        "encabezado_identidad": os.getenv("IDENTITY_HEADER", NOMBRE_ENCABEZADO_IDENTIDAD),
        "encabezado_correo": os.getenv("IDENTITY_EMAIL_HEADER", "X-Authenticated-Email"),
        "encabezado_grupos": os.getenv("IDENTITY_GROUPS_HEADER", "X-Authenticated-Groups"),
        "encabezado_nombre": os.getenv("IDENTITY_DISPLAY_NAME_HEADER", "X-Authenticated-Display-Name"),
        "encabezado_politica_mfa": os.getenv("MFA_POLICY_HEADER", "X-Auth-Mfa-Policy"),
        "encabezado_upstream_usuario": os.getenv("UPSTREAM_USER_HEADER", "X-Auth-Request-User"),
        "encabezado_upstream_preferred_username": os.getenv(
            "UPSTREAM_PREFERRED_USERNAME_HEADER",
            "X-Auth-Request-Preferred-Username",
        ),
        "encabezado_upstream_correo": os.getenv("UPSTREAM_EMAIL_HEADER", "X-Auth-Request-Email"),
        "encabezado_upstream_grupos": os.getenv("UPSTREAM_GROUPS_HEADER", "X-Auth-Request-Groups"),
        "username_source_order": os.getenv("IDENTITY_USERNAME_SOURCE_ORDER", "preferred_username,email,user"),
        "dominio_ad": os.getenv("AD_DOMAIN", os.getenv("USERDNSDOMAIN", "")).strip(),
        "dominio_corto_ad": os.getenv("AD_SHORT_DOMAIN", os.getenv("USERDOMAIN", "")).strip(),
        "servidor_ad": os.getenv("AD_SERVER", os.getenv("USERDNSDOMAIN", "")).strip(),
        "ad_search_base": os.getenv("AD_SEARCH_BASE", "").strip(),
        "ad_bind_user": os.getenv("AD_BIND_USER", "").strip(),
        "ad_bind_password": os.getenv("AD_BIND_PASSWORD", "").strip(),
        "tls_cert_path": os.getenv("TLS_CERT_PATH", ""),
        "tls_key_path": os.getenv("TLS_KEY_PATH", ""),
    }


cargar_variables_entorno_locales()
CONFIGURACION = obtener_configuracion()
# Consolidamos la configuracion de AD una sola vez para reutilizarla en todas las solicitudes.
DIRECTORY_CONFIG = DirectoryConfig(
    ad_server=CONFIGURACION["servidor_ad"],
    ad_domain=CONFIGURACION["dominio_ad"],
    ad_short_domain=CONFIGURACION["dominio_corto_ad"],
    ad_search_base=CONFIGURACION["ad_search_base"],
    ad_bind_user=CONFIGURACION["ad_bind_user"],
    ad_bind_password=CONFIGURACION["ad_bind_password"],
)
USERNAME_SOURCE_ORDER = tuple(
    fragmento.strip()
    for fragmento in CONFIGURACION["username_source_order"].split(",")
    if fragmento.strip()
)


class RespuestaSesionAuth(BaseModel):
    session_active: bool
    username: str
    email: str
    display_name: str
    groups: list[str]
    auth_mode: str
    source: str
    mfa_policy: str


class RespuestaAuthGroups(BaseModel):
    username: str
    groups: list[str]
    source: str


aplicacion = FastAPI(
    title="API de Autenticacion",
    version="1.0.0",
    docs_url="/auth/docs",
    openapi_url="/auth/openapi.json",
)


def _contexto_humano(
    request: Request,
    x_authenticated_user: str | None,
    x_authenticated_email: str | None,
    x_authenticated_groups: str | None,
    x_authenticated_display_name: str | None,
    x_auth_mfa_policy: str | None,
    preferred_username: str | None = None,
) -> AuthContext:
    # Esta funcion concentra la traduccion de headers del proxy a un contexto reusable.
    return resolver_contexto_proxy(
        request=request,
        username=x_authenticated_user,
        email=x_authenticated_email,
        display_name=x_authenticated_display_name,
        groups_header=x_authenticated_groups,
        mfa_policy=x_auth_mfa_policy,
        auth_mode=MODO_AUTENTICACION_PROXY,
        directory_config=DIRECTORY_CONFIG,
        preferred_username=preferred_username,
        username_source_order=USERNAME_SOURCE_ORDER,
    )


def _respuesta_sesion_inactiva() -> RespuestaSesionAuth:
    # Este contrato evita que el frontend trate la falta de sesion como error tecnico.
    return RespuestaSesionAuth(
        session_active=False,
        username="",
        email="",
        display_name="",
        groups=[],
        auth_mode=MODO_AUTENTICACION_PROXY,
        source="proxy_header",
        mfa_policy="",
    )


def _respuesta_sesion(contexto: AuthContext) -> RespuestaSesionAuth:
    return RespuestaSesionAuth(
        session_active=contexto.session_active,
        username=contexto.username,
        email=contexto.email,
        display_name=contexto.display_name,
        groups=contexto.groups,
        auth_mode=contexto.auth_mode,
        source=contexto.source,
        mfa_policy=contexto.mfa_policy,
    )


@aplicacion.get("/health")
def obtener_salud() -> dict[str, object]:
    return {
        "status": "ok",
        "service": "auth",
        "auth_mode": MODO_AUTENTICACION_PROXY,
        "tls_cert_configured": bool(CONFIGURACION["tls_cert_path"]),
        "tls_key_configured": bool(CONFIGURACION["tls_key_path"]),
    }


@aplicacion.get("/auth/health")
def obtener_salud_auth() -> dict[str, str]:
    return {"status": "ok", "service": "auth", "auth_mode": MODO_AUTENTICACION_PROXY}


@aplicacion.get("/auth/ad-health")
def obtener_salud_ad() -> dict[str, str | int]:
    servidor_ad = CONFIGURACION["servidor_ad"]
    if not servidor_ad:
        raise HTTPException(status_code=500, detail="No hay servidor AD configurado.")

    try:
        with socket.create_connection((servidor_ad, 389), timeout=5):
            pass
    except OSError as exc:
        raise HTTPException(status_code=502, detail=f"No se pudo conectar a AD en {servidor_ad}:389") from exc

    return {
        "status": "ok",
        "ad_server": servidor_ad,
        "ad_domain": CONFIGURACION["dominio_ad"],
        "ad_short_domain": CONFIGURACION["dominio_corto_ad"],
        "port": 389,
    }


@aplicacion.get("/auth/login")
def iniciar_login(rd: str = Query(default="/auth/me")) -> RedirectResponse:
    # Dejamos el inicio de sesion visible como endpoint del servicio de auth.
    return RedirectResponse(url=f"/oauth2/start?{urlencode({'rd': rd})}", status_code=302)


@aplicacion.get("/auth/callback")
def callback_login(code: str | None = Query(default=None), state: str | None = Query(default=None)) -> RedirectResponse:
    # Reenviamos exactamente los parametros que devuelve Entra ID hacia oauth2-proxy.
    parametros: dict[str, str] = {}
    if code:
        parametros["code"] = code
    if state:
        parametros["state"] = state
    suffix = f"?{urlencode(parametros)}" if parametros else ""
    return RedirectResponse(url=f"/oauth2/callback{suffix}", status_code=302)


@aplicacion.post("/auth/logout")
def cerrar_sesion(rd: str = Query(default="/")) -> RedirectResponse:
    return RedirectResponse(url=f"/oauth2/sign_out?{urlencode({'rd': rd})}", status_code=302)


@aplicacion.get("/auth/proxy-identity")
def obtener_identidad_proxy_normalizada(
    request: Request,
    x_auth_request_user: Annotated[str | None, Header(alias=CONFIGURACION["encabezado_upstream_usuario"])] = None,
    x_auth_request_preferred_username: Annotated[
        str | None,
        Header(alias=CONFIGURACION["encabezado_upstream_preferred_username"]),
    ] = None,
    x_auth_request_email: Annotated[str | None, Header(alias=CONFIGURACION["encabezado_upstream_correo"])] = None,
    x_auth_request_groups: Annotated[str | None, Header(alias=CONFIGURACION["encabezado_upstream_grupos"])] = None,
) -> Response:
    # Este endpoint existe para que nginx normalice una sola vez la identidad y la reenvie a cualquier backend.
    contexto = _contexto_humano(
        request,
        x_auth_request_user,
        x_auth_request_email,
        x_auth_request_groups,
        None,
        "entra_standard",
        preferred_username=x_auth_request_preferred_username,
    )
    return Response(
        status_code=204,
        headers={
            "X-Identity-Username": contexto.username,
            "X-Identity-Email": contexto.email,
            "X-Identity-Groups": ",".join(contexto.groups),
            "X-Identity-Display-Name": contexto.display_name,
        },
    )


@aplicacion.get("/auth/session", response_model=RespuestaSesionAuth)
def obtener_sesion_actual(
    request: Request,
    x_authenticated_user: Annotated[str | None, Header(alias=CONFIGURACION["encabezado_identidad"])] = None,
    x_authenticated_email: Annotated[str | None, Header(alias=CONFIGURACION["encabezado_correo"])] = None,
    x_authenticated_groups: Annotated[str | None, Header(alias=CONFIGURACION["encabezado_grupos"])] = None,
    x_authenticated_display_name: Annotated[str | None, Header(alias=CONFIGURACION["encabezado_nombre"])] = None,
    x_auth_mfa_policy: Annotated[str | None, Header(alias=CONFIGURACION["encabezado_politica_mfa"])] = None,
) -> RespuestaSesionAuth:
    try:
        contexto = _contexto_humano(
            request,
            x_authenticated_user,
            x_authenticated_email,
            x_authenticated_groups,
            x_authenticated_display_name,
            x_auth_mfa_policy,
        )
    except HTTPException as exc:
        if exc.status_code == 401:
            return _respuesta_sesion_inactiva()
        raise
    return _respuesta_sesion(contexto)


@aplicacion.get("/auth/me", response_model=RespuestaSesionAuth)
def obtener_mi_identidad(
    request: Request,
    x_authenticated_user: Annotated[str | None, Header(alias=CONFIGURACION["encabezado_identidad"])] = None,
    x_authenticated_email: Annotated[str | None, Header(alias=CONFIGURACION["encabezado_correo"])] = None,
    x_authenticated_groups: Annotated[str | None, Header(alias=CONFIGURACION["encabezado_grupos"])] = None,
    x_authenticated_display_name: Annotated[str | None, Header(alias=CONFIGURACION["encabezado_nombre"])] = None,
    x_auth_mfa_policy: Annotated[str | None, Header(alias=CONFIGURACION["encabezado_politica_mfa"])] = None,
) -> RespuestaSesionAuth:
    contexto = _contexto_humano(
        request,
        x_authenticated_user,
        x_authenticated_email,
        x_authenticated_groups,
        x_authenticated_display_name,
        x_auth_mfa_policy,
    )
    return _respuesta_sesion(contexto)


@aplicacion.get("/auth/groups", response_model=RespuestaAuthGroups)
def obtener_grupos_actuales(
    request: Request,
    x_authenticated_user: Annotated[str | None, Header(alias=CONFIGURACION["encabezado_identidad"])] = None,
    x_authenticated_email: Annotated[str | None, Header(alias=CONFIGURACION["encabezado_correo"])] = None,
    x_authenticated_groups: Annotated[str | None, Header(alias=CONFIGURACION["encabezado_grupos"])] = None,
    x_authenticated_display_name: Annotated[str | None, Header(alias=CONFIGURACION["encabezado_nombre"])] = None,
    x_auth_mfa_policy: Annotated[str | None, Header(alias=CONFIGURACION["encabezado_politica_mfa"])] = None,
) -> RespuestaAuthGroups:
    contexto = _contexto_humano(
        request,
        x_authenticated_user,
        x_authenticated_email,
        x_authenticated_groups,
        x_authenticated_display_name,
        x_auth_mfa_policy,
    )
    return RespuestaAuthGroups(username=contexto.username, groups=contexto.groups, source=contexto.source)


app = aplicacion
