from __future__ import annotations

import hmac
import os
import re
from dataclasses import dataclass
from typing import Any

from fastapi import Header, HTTPException, Request
from ldap3 import ALL, Connection, NTLM, Server


SEPARADOR_GRUPOS_RE = re.compile(r"[,\n;|]+")
ENCABEZADO_PROXY_INTERNO = "X-Internal-Proxy"
VALOR_PROXY_INTERNO = "nginx-local"


@dataclass(frozen=True)
class DirectoryConfig:
    ad_server: str
    ad_domain: str
    ad_short_domain: str
    ad_search_base: str
    ad_bind_user: str
    ad_bind_password: str


@dataclass(frozen=True)
class AuthContext:
    username: str
    email: str
    display_name: str
    groups: list[str]
    auth_mode: str
    mfa_policy: str
    source: str
    session_active: bool


def limpiar_usuario(valor: str | None) -> str:
    return (valor or "").strip()


def normalizar_grupos_desde_header(valor: str | None) -> list[str]:
    texto = (valor or "").strip()
    if not texto:
        return []

    grupos: list[str] = []
    vistos: set[str] = set()
    for fragmento in SEPARADOR_GRUPOS_RE.split(texto):
        grupo = fragmento.strip()
        if not grupo:
            continue
        clave = grupo.casefold()
        if clave in vistos:
            continue
        vistos.add(clave)
        grupos.append(grupo)
    return grupos


def validar_origen_proxy_local(request: Request) -> None:
    # Solo confiamos en headers de identidad cuando nginx marca la solicitud como interna.
    host_cliente = request.client.host if request.client else ""
    marca_proxy = (request.headers.get(ENCABEZADO_PROXY_INTERNO) or "").strip()
    if marca_proxy == VALOR_PROXY_INTERNO:
        return

    if host_cliente not in {"127.0.0.1", "::1", "localhost"}:
        raise HTTPException(
            status_code=403,
            detail="Acceso denegado: esta ruta solo acepta solicitudes reenviadas por el proxy local.",
        )


def _build_bind_user(directory_config: DirectoryConfig) -> str:
    if directory_config.ad_bind_user:
        return directory_config.ad_bind_user

    userdomain = os.getenv("USERDOMAIN", "").strip()
    username = os.getenv("USERNAME", "").strip()
    if userdomain and username:
        return f"{userdomain}\\{username}"
    return ""


def _connection_kwargs(bind_user: str, bind_password: str) -> dict[str, Any]:
    kwargs: dict[str, Any] = {"auto_bind": True}
    if bind_user:
        kwargs["user"] = bind_user
        kwargs["password"] = bind_password
        if "\\" in bind_user and "@" not in bind_user:
            kwargs["authentication"] = NTLM
    return kwargs


def consultar_atributos_usuario(*, username: str, directory_config: DirectoryConfig) -> dict[str, Any]:
    # Si AD no esta configurado, dejamos que el servicio funcione solo con headers del proxy.
    if not directory_config.ad_server or not directory_config.ad_search_base or not username:
        return {}

    bind_user = _build_bind_user(directory_config)
    bind_password = directory_config.ad_bind_password
    servidor = Server(directory_config.ad_server, get_info=ALL)
    atributos = ["sAMAccountName", "displayName", "mail", "memberOf", "userPrincipalName"]

    for atributo, valor in _candidate_username_values(username, directory_config):
        filtro = f"(&(objectClass=user)({atributo}={_escape_ldap_filter_value(valor)}))"
        try:
            with Connection(servidor, **_connection_kwargs(bind_user, bind_password)) as conexion:
                encontrado = conexion.search(
                    search_base=directory_config.ad_search_base,
                    search_filter=filtro,
                    attributes=atributos,
                    size_limit=1,
                )
                if not encontrado or not conexion.entries:
                    continue

                entrada = conexion.entries[0]
                return {
                    "display_name": _entry_value(entrada, "displayName"),
                    "email": _entry_value(entrada, "mail") or _entry_value(entrada, "userPrincipalName"),
                    "groups": _member_of_to_names(_entry_list(entrada, "memberOf")),
                }
        except Exception:
            return {}

    return {}


def _candidate_username_values(username: str, directory_config: DirectoryConfig) -> list[tuple[str, str]]:
    usuario = username.strip()
    if not usuario:
        return []

    candidatos: list[tuple[str, str]] = []
    if "\\" in usuario:
        dominio, nombre = usuario.split("\\", 1)
        candidatos.append(("sAMAccountName", nombre))
        if dominio:
            candidatos.append(("userPrincipalName", f"{nombre}@{directory_config.ad_domain or dominio}"))
    elif "@" in usuario:
        nombre = usuario.split("@", 1)[0]
        candidatos.append(("userPrincipalName", usuario))
        candidatos.append(("sAMAccountName", nombre))
    else:
        candidatos.append(("sAMAccountName", usuario))
        if directory_config.ad_domain:
            candidatos.append(("userPrincipalName", f"{usuario}@{directory_config.ad_domain}"))

    vistos: set[tuple[str, str]] = set()
    resultado: list[tuple[str, str]] = []
    for candidato in candidatos:
        if candidato in vistos:
            continue
        vistos.add(candidato)
        resultado.append(candidato)
    return resultado


def _escape_ldap_filter_value(value: str) -> str:
    return (
        value.replace("\\", r"\5c")
        .replace("*", r"\2a")
        .replace("(", r"\28")
        .replace(")", r"\29")
        .replace("\x00", r"\00")
    )


def _entry_value(entry: Any, attr: str) -> str:
    if not hasattr(entry, attr):
        return ""
    value = getattr(entry, attr).value
    return "" if value is None else str(value).strip()


def _entry_list(entry: Any, attr: str) -> list[str]:
    if not hasattr(entry, attr):
        return []
    value = getattr(entry, attr).value
    if value is None:
        return []
    if isinstance(value, list):
        return [str(item).strip() for item in value if str(item).strip()]
    return [str(value).strip()]


def _member_of_to_names(member_of_values: list[str]) -> list[str]:
    grupos: list[str] = []
    vistos: set[str] = set()
    for dn in member_of_values:
        nombre = dn
        for fragmento in dn.split(","):
            if fragmento.upper().startswith("CN="):
                nombre = fragmento[3:]
                break
        clave = nombre.casefold()
        if clave in vistos:
            continue
        vistos.add(clave)
        grupos.append(nombre)
    return grupos


def resolver_contexto_proxy(
    *,
    request: Request,
    username: str | None,
    email: str | None,
    display_name: str | None,
    groups_header: str | None,
    mfa_policy: str | None,
    auth_mode: str,
    directory_config: DirectoryConfig,
) -> AuthContext:
    validar_origen_proxy_local(request)

    usuario = limpiar_usuario(username)
    if not usuario:
        raise HTTPException(status_code=401, detail="No hay identidad autenticada en la solicitud proxied.")

    grupos = normalizar_grupos_desde_header(groups_header)
    correo = (email or "").strip()
    nombre_mostrar = (display_name or "").strip()

    if not grupos or not correo or not nombre_mostrar:
        atributos = consultar_atributos_usuario(username=usuario, directory_config=directory_config)
        grupos = grupos or atributos.get("groups", [])
        correo = correo or str(atributos.get("email", "")).strip()
        nombre_mostrar = nombre_mostrar or str(atributos.get("display_name", "")).strip()

    return AuthContext(
        username=usuario,
        email=correo,
        display_name=nombre_mostrar,
        groups=grupos,
        auth_mode=auth_mode,
        mfa_policy=(mfa_policy or "").strip(),
        source="proxy_header",
        session_active=True,
    )


def validar_api_key(x_api_key: str | None = Header(default=None, alias="X-Api-Key")) -> str:
    api_key = (x_api_key or "").strip()
    keys = [valor.strip() for valor in os.getenv("SYSTEM_API_KEYS", "").split(",") if valor.strip()]
    if not keys:
        raise HTTPException(status_code=503, detail="No hay API keys tecnicas configuradas.")

    for candidate in keys:
        if hmac.compare_digest(api_key, candidate):
            return api_key

    raise HTTPException(status_code=401, detail="API key tecnica invalida.")
