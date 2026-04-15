# nginx para API de autenticacion

Este directorio contiene la publicacion HTTPS soportada de `API_Autenticacion`.

## Archivos activos

- `nginx/conf/app.docker.conf`: configuracion del despliegue real con Docker
- `nginx/conf/app.conf`: variante local sin Docker
- `start_nginx.ps1`: arranque o recarga local de `nginx`
- `start_oauth2_proxy.ps1`: arranque local de `oauth2-proxy`
- `start_auth_api.ps1`: arranque local de FastAPI
- `start_stack_entra.ps1`: arranque conjunto del stack local

## Runtime esperado

- `auth-api`: `127.0.0.1:8001`
- `oauth2-proxy`: `127.0.0.1:4180`
- `nginx`: `443` para `e3display.com`
- `nginx`: `4441` para apps humanas completas publicadas por listener dedicado

## Flujo principal

- `/oauth2/` se reenvia a `oauth2-proxy`
- `/oauth2/auth` se usa como subrequest de validacion de sesion
- `/auth/*` en `443` sigue usando `/_auth/proxy-identity` para normalizar identidad reusable
- `4441` valida sesion con `auth_request /oauth2/auth`, normaliza identidad inline y reenvia `X-Authenticated-*` al backend final

## Entra ID

Variables minimas requeridas:

- `ENTRA_TENANT_ID`
- `OAUTH2_PROXY_CLIENT_ID`
- `OAUTH2_PROXY_CLIENT_SECRET`
- `OAUTH2_PROXY_COOKIE_SECRET`
- `OAUTH2_PROXY_REDIRECT_URL=https://e3display.com:4441/oauth2/callback`
- `OAUTH2_PROXY_PROMPT=select_account`

La Redirect URI registrada en Entra ID para el listener `4441` debe ser exactamente:

- `https://e3display.com:4441/oauth2/callback`

## TLS

La configuracion soportada termina TLS en este mismo repo:

- `443` para `https://e3display.com`
- `4441` para `https://e3display.com:4441`

En Docker Compose, los certificados se montan en:

- `/etc/nginx/certs/fullchain.crt`
- `/etc/nginx/certs/private.key`

## Patron reusable para servicios humanos

`e3os_entraid` queda como servicio de referencia:

- listener HTTPS dedicado: `4441`
- backend Docker endurecido: `192.168.2.31:5001`
- backend local: `127.0.0.1:5001`

El listener dedicado debe:

- vivir en raiz `/`
- validar sesion con `auth_request /oauth2/auth`
- reenviar `X-Authenticated-*` y `X-Internal-Proxy`
- conservar `Host` con puerto cuando el callback dependa del listener especifico
## Logout federado

- `/oauth2/sign_out` se intercepta antes de `oauth2-proxy` y pasa por `auth-api`
- `auth-api` construye el redirect hacia `https://login.microsoftonline.com/<tenant>/oauth2/v2.0/logout`
- `oauth2-proxy` sigue limpiando su cookie local en `/oauth2/_proxy_sign_out`
- el retorno post-logout vuelve a `/auth/login` y el siguiente login se solicita con `prompt=select_account`
