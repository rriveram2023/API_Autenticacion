# nginx para API de autenticacion

Este directorio contiene la publicacion HTTPS de `API_Autenticacion`.

## Componentes

- `nginx/conf/app.conf`: proxy de entrada principal para `e3display.com`
- `nginx/conf/app.docker.conf`: proxy de entrada para despliegue con Docker Compose
- `nginx/conf/app.docker.shared.conf`: proxy HTTP interno para VM compartida detras de un proxy frontal
- `start_nginx.ps1`: localiza `nginx.exe`, prepara directorios temporales y levanta o recarga la configuracion
- `start_oauth2_proxy.ps1`: arranca `oauth2-proxy` con proveedor `entra-id`
- `start_auth_api.ps1`: arranca FastAPI en `127.0.0.1:8001`
- `start_stack_entra.ps1`: arranque conjunto del stack de autenticacion

## Runtime esperado

- `API de autenticacion`: `127.0.0.1:8001`
- `oauth2-proxy`: `127.0.0.1:4180`
- `nginx`: `443` publico para `e3display.com`

## Flujo HTTP

- `/oauth2/` se reenvia a `oauth2-proxy`
- `/oauth2/auth` se usa como subrequest de validacion de sesion
- `/auth/login` y `/auth/callback` pasan por `API de autenticacion`
- `/auth/*` queda protegido con `auth_request`
- `/health` publica la salud basica del backend de autenticacion

## Entra ID

Variables minimas requeridas en `.env`:

- `ENTRA_TENANT_ID`
- `OAUTH2_PROXY_CLIENT_ID`
- `OAUTH2_PROXY_CLIENT_SECRET`
- `OAUTH2_PROXY_COOKIE_SECRET`
- `OAUTH2_PROXY_REDIRECT_URL=https://e3display.com/auth/callback`

La app registrada en Entra ID debe aceptar exactamente:

- `https://e3display.com/auth/callback`

## TLS

La configuracion actual usa TLS en `443` y fuerza redireccion desde `80`.

Revisa que `nginx/conf/app.conf` apunte al certificado real:

- `ssl_certificate`
- `ssl_certificate_key`

El `.env.example` tambien expone referencias utiles:

- `TLS_CERT_PATH`
- `TLS_KEY_PATH`
- `PYTHON_EXE_PATH`
- `NGINX_EXE_PATH`
- `OAUTH2_PROXY_EXE_PATH`

En Docker Compose, la configuracion equivalente vive en `.env.docker` y los certificados se montan en:

- `/etc/nginx/certs/fullchain.crt`
- `/etc/nginx/certs/private.key`

Para una VM compartida, la variante recomendada es no terminar TLS aqui. En ese caso:

- `nginx/conf/app.docker.shared.conf` escucha solo HTTP interno
- el stack se publica por ejemplo en `8081`
- un proxy frontal comun del host o de la infraestructura recibe `80/443`

## Variante trusted network

Existe un ejemplo opcional en `nginx/conf/app_trusted_network.example.conf` para marcar:

- `X-Auth-Mfa-Policy=trusted_network`

Ese archivo sirve como referencia de una segunda entrada con politica distinta, pero este repositorio mantiene como foco el frente principal de autenticacion.

## Patron reusable para servicios humanos

El servicio `e3os_entraid` queda como ejemplo base para publicar apps humanas nuevas sin subpath:

- listener HTTPS directo: `4441`
- listener interno para VM compartida: `8088`
- backend local: `127.0.0.1:5001`
- backend desde Docker: `host.docker.internal:5001`

Para agregar otro servicio, duplica su `upstream` y su `server`, cambia backend y puerto, y conserva el bloque de headers internos autenticados.