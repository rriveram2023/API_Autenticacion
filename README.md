# API_Autenticacion

Repositorio dedicado a autenticacion para `e3display.com`.

Este repo contiene solo el stack de autenticacion:

- `Auth API` en FastAPI
- `oauth2-proxy` con proveedor `entra-id`
- `nginx` como front door HTTPS y proxy inverso
- scripts de soporte para cookie secret, hosts y validacion TLS

Tambien puede publicar otras APIs FastAPI detras del mismo `nginx`, siempre que confien solo en headers internos reenviados por el proxy.

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

El mismo patron puede reutilizarse para publicar rutas humanas de otros servicios, por ejemplo `folder-api`, sin compartir codigo Python entre repos.

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

## Docker

El repo incluye una ruta de despliegue en contenedores para servidor:

- `Dockerfile`: imagen de `auth-api`
- `docker-compose.yml`: stack con `auth-api`, `oauth2-proxy` y `nginx`
- `docker-compose.vm-shared.yml`: variante recomendada para VM compartida sin publicar `443` desde este stack
- `.env.docker.example`: variables base para despliegue
- `nginx/conf/app.docker.conf`: configuracion `nginx` para contenedores
- `nginx/conf/app.docker.shared.conf`: configuracion HTTP interna para VM compartida
- `docs/arquitectura.md`: diagramas Mermaid de las opciones de despliegue
- `docs/vm_remote_ssh.md`: guia de acceso remoto a la VM con VS Code

Flujo recomendado:

1. Copia el archivo de entorno:

```powershell
Copy-Item .env.docker.example .env.docker
```

2. Coloca certificados reales en `nginx/certs/`:

- `nginx/certs/fullchain.crt`
- `nginx/certs/private.key`

3. Completa en `.env.docker`:

- `ENTRA_TENANT_ID`
- `OAUTH2_PROXY_CLIENT_ID`
- `OAUTH2_PROXY_CLIENT_SECRET`
- `OAUTH2_PROXY_COOKIE_SECRET`
- `OAUTH2_PROXY_REDIRECT_URL`
- `AD_*` si vas a enriquecer identidad desde LDAP/AD

4. Levanta el stack:

```powershell
docker compose --env-file .env.docker up -d --build
```

5. Revisa estado y logs:

```powershell
docker compose ps
docker compose logs -f auth-api
docker compose logs -f oauth2-proxy
docker compose logs -f nginx
```

6. Para apagarlo:

```powershell
docker compose down
```

Notas:

- En Docker, `nginx` ya no usa rutas Windows ni `127.0.0.1`; usa `auth-api` y `oauth2-proxy` como nombres de servicio.
- Si el servidor debe consultar AD, el contenedor `auth-api` necesita conectividad de red hacia el dominio y el puerto LDAP correspondiente.

## VM compartida

Para una VM `Windows Server` compartida con mas aplicaciones, la recomendacion es no dejar `80/443` exclusivos a este repo.

Arquitectura recomendada:

- un proxy frontal compartido recibe `80/443`
- ese proxy maneja TLS y certificados
- el stack de este repo se publica internamente en `8081`
- el `nginx` del repo sigue haciendo `auth_request`, integra `oauth2-proxy` y reenvia a `auth-api`

Para levantar esa variante:

```powershell
docker compose -f docker-compose.vm-shared.yml --env-file .env.docker up -d --build
```

En ese modo, la URL publica sigue siendo `https://e3display.com`, pero el TLS ya no vive en este compose.

## VS Code Remote SSH

Flujo recomendado para operar y seguir desarrollando sobre la VM:

1. Instala y habilita `OpenSSH Server` en la VM.
2. Clona el repo en una ruta estable, por ejemplo:

```text
D:\Repos\API_Autenticacion
```

3. Abre la VM desde `VS Code Remote SSH`.
4. Trabaja dentro de esa carpeta remota:

- Git corre en la VM
- `docker compose` corre en la VM
- logs, `exec`, `ps` y validaciones ocurren sobre el entorno real
- Codex debe abrirse en esa misma ventana remota para compartir contexto con el despliegue activo

Guia detallada:

- `docs/vm_remote_ssh.md`

## TLS

Hay dos opciones validas:

- `TLS dentro del stack`: util para local, laboratorio o una VM dedicada
- `TLS en proxy frontal compartido`: recomendado para tu VM compartida

La recomendacion para produccion en tu caso es:

- dejar TLS fuera de este compose
- mantener el `nginx` del repo como proxy interno de autenticacion

Para documentar las dos opciones, consulta:

- `docs/arquitectura.md`

## Como usa este servicio tu equipo y otras aplicaciones

Que el contenedor este activo no significa que otras aplicaciones entren al contenedor directamente. Lo correcto es consumir el servicio publicado por su URL o por el proxy frontal.

Uso humano:

- los usuarios entran por la URL publica, por ejemplo `https://e3display.com`
- `nginx` y `oauth2-proxy` manejan el login con Entra ID
- despues el backend expone identidad, sesion y grupos

Uso por otras aplicaciones web:

- otra app puede delegar autenticacion enviando al usuario a las rutas publicadas por este stack
- tambien puede colocarse detras del mismo proxy frontal y reutilizar el patron `auth_request`
- esa app no necesita hablar con Docker internamente; consume la URL interna o publica definida en la arquitectura

Uso por otros backends o APIs:

- si necesitan validar una sesion humana, pueden consumir rutas como:
  - `GET /auth/session`
  - `GET /auth/me`
  - `GET /auth/groups`
- deben hacerlo a traves del frente que preserve cookies o headers de autenticacion del usuario

Uso dentro de la VM compartida:

- el proxy frontal compartido recibe `80/443`
- reenvia a este stack en `http://<host-vm>:8081`
- por eso, otras aplicaciones de la misma VM o del mismo entorno deben integrarse contra:
  - la URL publica `https://e3display.com`, si el flujo es de usuario final
  - la URL interna del stack, por ejemplo `http://<host-vm>:8081`, si el trafico viene desde el proxy comun o una capa de infraestructura

Regla practica:

- para personas: usa la URL publica
- para infraestructura compartida en la VM: usa el puerto interno publicado del stack
- para desarrollo/operacion: entra por `VS Code Remote SSH` y administra el compose remoto

### Lectura operativa

Cuando preguntes "quien consume este servicio", piensa en cuatro clientes distintos:

- navegador del usuario final
- proxy frontal compartido
- aplicacion web que delega autenticacion
- backend que consulta identidad o sesion

Cada uno espera algo distinto:

- navegador: redirecciones a Entra ID, cookies de sesion y respuestas HTML o JSON
- proxy frontal: un upstream HTTP estable, por ejemplo `http://<host-vm>:8081`
- app web: una URL publica estable y headers de identidad reenviados por el proxy
- backend: respuestas JSON como `/auth/session`, `/auth/me` y `/auth/groups`

## Integracion con Folder API

`API_Autenticacion` puede proteger y publicar las rutas humanas de `CreacionCarpetasM`:

- `GET /folders/create/browser`
- `POST /folders/create`
- `GET /folders/docs`
- `GET /folders/openapi.json`

En este esquema:

- `folder-api` sigue corriendo como servicio separado
- `nginx` exige sesion de usuario para las rutas humanas
- `nginx` reenvia `X-Authenticated-*` y `X-Internal-Proxy`
- `POST /folders/create/system` queda fuera del flujo humano y sigue siendo tecnico

## Docker con HTTPS directo en la VM

Si quieres que este repo termine TLS por si mismo, usa `docker-compose.yml` en lugar de `docker-compose.vm-shared.yml`.

Requisitos:

- una VM dedicada o una VM donde este stack pueda tomar `80` y `443`
- certificados reales colocados localmente en `nginx/certs/`
- estos dos archivos exactos:
  - `nginx/certs/fullchain.crt`
  - `nginx/certs/private.key`

Arranque recomendado:

Primero deten la variante `vm-shared` si esta corriendo, porque ambas usan los mismos nombres de contenedor y este modo necesita `80/443`:

```powershell
docker compose -f docker-compose.vm-shared.yml --env-file .env.docker down
docker compose -f docker-compose.yml --env-file .env.docker up -d --build
```

Validacion rapida:

```powershell
curl.exe -k -sS -i --max-time 10 https://localhost/health
curl.exe -k -sS -i --max-time 10 https://localhost/auth/health
curl.exe -k -sS -i --max-time 10 --max-redirs 0 https://localhost/auth/session
```

Comportamiento esperado:

- `https://localhost/health` responde `200 OK`
- `https://localhost/auth/health` responde `200 OK`
- `https://localhost/auth/session` sin sesion responde `302` hacia `/oauth2/start?...`
- `http://localhost/...` redirige a `https://localhost/...`

Si faltan `fullchain.crt` o `private.key`, `nginx` no podra iniciar en modo HTTPS directo.
