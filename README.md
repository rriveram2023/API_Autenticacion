# API_Autenticacion

Repositorio dedicado a autenticacion para `e3display.com`.

Este repo contiene solo el stack de autenticacion:

- `Auth API` en FastAPI
- `oauth2-proxy` con proveedor `entra-id`
- `nginx` como front door HTTPS y proxy inverso
- scripts de soporte para cookie secret, hosts y validacion TLS

## Estructura

- `services/auth_api`: servicio principal de autenticacion y sesion
- `nginx/conf/app.conf`: publicacion HTTPS y proteccion con `auth_request`
- `nginx/start_auth_api.ps1`: levanta FastAPI en `127.0.0.1:8001`
- `nginx/start_oauth2_proxy.ps1`: levanta `oauth2-proxy` en `127.0.0.1:4180`
- `nginx/start_nginx.ps1`: levanta o recarga `nginx`
- `nginx/start_stack_entra.ps1`: levanta el stack completo de autenticacion
- `scripts/`: utilidades para TLS, hosts y cookie secret

## Flujo de autenticacion

1. El navegador entra por `https://e3display.com`.
2. `nginx` protege `/auth/` con `auth_request` hacia `oauth2-proxy`.
3. Si no hay sesion, `nginx` redirige a `/oauth2/start`.
4. `oauth2-proxy` autentica contra Microsoft Entra ID.
5. En el callback, `Auth API` redirige a `/oauth2/callback`.
6. `oauth2-proxy` establece la sesion y `nginx` reenvia headers confiables al backend:
   - `X-Authenticated-User`
   - `X-Authenticated-Email`
   - `X-Authenticated-Groups`
   - `X-Authenticated-Display-Name`
   - `X-Auth-Mfa-Policy`
   - `X-Internal-Proxy`
7. `Auth API` expone sesion, identidad y grupos con base en esos headers y, si hace falta, enriquece datos desde AD.

## Endpoints principales

- `GET /auth/login`
- `GET /auth/callback`
- `POST /auth/logout`
- `GET /auth/session`
- `GET /auth/me`
- `GET /auth/groups`
- `GET /auth/health`
- `GET /auth/ad-health`
- `GET /auth/docs`
- `GET /health`

## Variables de entorno clave

Base:

- `AUTH_API_HOST=127.0.0.1`
- `AUTH_API_PORT=8001`
- `NGINX_PORT=443`
- `NGINX_PUBLIC_HOST=e3display.com`
- `NGINX_PUBLIC_SCHEME=https`

Entra ID y sesion:

- `ENTRA_TENANT_ID`
- `OAUTH2_PROXY_CLIENT_ID`
- `OAUTH2_PROXY_CLIENT_SECRET`
- `OAUTH2_PROXY_COOKIE_SECRET`
- `OAUTH2_PROXY_REDIRECT_URL=https://e3display.com/auth/callback`
- `OAUTH2_PROXY_ALLOWED_GROUPS`
- `OAUTH2_PROXY_WHITELIST_DOMAINS`

Headers confiables:

- `IDENTITY_HEADER`
- `IDENTITY_EMAIL_HEADER`
- `IDENTITY_GROUPS_HEADER`
- `IDENTITY_DISPLAY_NAME_HEADER`
- `MFA_POLICY_HEADER`

Active Directory opcional:

- `AD_SERVER`
- `AD_DOMAIN`
- `AD_SHORT_DOMAIN`
- `AD_SEARCH_BASE`
- `AD_BIND_USER`
- `AD_BIND_PASSWORD`

TLS:

- `TLS_CERT_PATH`
- `TLS_KEY_PATH`

## TLS

`nginx` termina TLS en `443` y redirige `80` a HTTPS. El ejemplo de `.env.example` apunta a certificados dentro del repo:

- `nginx/certs/fullchain.crt`
- `nginx/certs/private.key`

La configuracion activa de `nginx/conf/app.conf` ya apunta a la estructura local de este repo.

## Runtime local

Para que el stack sea autocontenido en esta carpeta, el runtime local esperado es:

- `.venv/`
- `nginx-bin/`
- `oauth2-proxy-bin/`
- `nginx/certs/`

Todos esos directorios quedan fuera de Git por medio de `.gitignore`.

## Arranque local

1. Crea `.env` a partir de `.env.example`.
2. Coloca certificados TLS validos en `nginx/certs/`.
3. Asegura que en Entra ID exista la redirect URI `https://e3display.com/auth/callback`.
4. Genera `OAUTH2_PROXY_COOKIE_SECRET` con `.\scripts\generar_cookie_secret.ps1`.
5. Si el nombre no resuelve localmente, ajusta hosts con `.\scripts\actualizar_hosts_e3display.ps1`.
6. Levanta el stack:

```powershell
.\nginx\start_stack_entra.ps1
```

## Verificacion rapida

- `https://e3display.com/auth/docs`
- `https://e3display.com/auth/session`
- `https://e3display.com/auth/me`
- `https://e3display.com/auth/groups`
- `https://e3display.com/auth/health`
- `https://e3display.com/auth/ad-health`
