# API_Autenticacion

Servicio de autenticacion para `e3display.com` basado en:

- `FastAPI` para sesion, identidad y grupos
- `oauth2-proxy` con proveedor `entra-id`
- `nginx` como proxy de entrada y terminacion HTTPS o proxy interno, segun el modo de despliegue

Este repositorio publica el frente de autenticacion y puede proteger rutas humanas de otros servicios que confien en los headers internos reenviados por `nginx`.

## Que resuelve

- login humano con Microsoft Entra ID
- sesion HTTP manejada por `oauth2-proxy`
- endpoints para consultar sesion, identidad y grupos
- enriquecimiento opcional desde Active Directory
- despliegue tanto en Docker con HTTPS propio como en VM compartida detras de un proxy frontal

## Componentes principales

- `services/auth_api/app.py`: API principal y endpoints `/auth/*`
- `services/auth_api/identity.py`: validacion de headers internos y enriquecimiento desde AD
- `docker-compose.yml`: despliegue con HTTPS directo en `80/443`
- `docker-compose.vm-shared.yml`: despliegue HTTP interno en `8081` para VM compartida
- `nginx/conf/app.docker.conf`: `nginx` para HTTPS directo
- `nginx/conf/app.docker.shared.conf`: `nginx` para VM compartida
- `docs/vm_remote_ssh.md`: operacion remota desde VS Code
- `docs/arquitectura.md`: vista de arquitectura por escenario

## Flujo de autenticacion

1. El usuario entra por `https://e3display.com`.
2. `nginx` protege `/auth/` con `auth_request` hacia `oauth2-proxy`.
3. Si no existe sesion, `nginx` redirige a `/oauth2/start`.
4. `oauth2-proxy` autentica contra Microsoft Entra ID.
5. Al regresar del callback, `nginx` reenvia al backend solo headers internos confiables.
6. `Auth API` expone sesion, identidad y grupos; si hace falta, completa datos desde Active Directory.

Headers internos esperados:

- `X-Authenticated-User`
- `X-Authenticated-Email`
- `X-Authenticated-Groups`
- `X-Authenticated-Display-Name`
- `X-Auth-Mfa-Policy`
- `X-Internal-Proxy`

## Endpoints principales

- `GET /health`
- `GET /auth/health`
- `GET /auth/ad-health`
- `GET /auth/login`
- `GET /auth/callback`
- `POST /auth/logout`
- `GET /auth/session`
- `GET /auth/me`
- `GET /auth/groups`
- `GET /auth/docs`

## Variables de entorno importantes

Base:

- `AUTH_API_HOST`
- `AUTH_API_PORT`
- `NGINX_PUBLIC_HOST`
- `NGINX_PUBLIC_SCHEME`

Entra ID:

- `ENTRA_TENANT_ID`
- `OAUTH2_PROXY_CLIENT_ID`
- `OAUTH2_PROXY_CLIENT_SECRET`
- `OAUTH2_PROXY_COOKIE_SECRET`
- `OAUTH2_PROXY_REDIRECT_URL`
- `OAUTH2_PROXY_WHITELIST_DOMAINS`

Headers internos:

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

## Modos de despliegue

### 1. HTTPS directo en este repo

Usa este modo cuando el propio stack debe tomar `80/443` y terminar TLS.

Archivos clave:

- `docker-compose.yml`
- `nginx/conf/app.docker.conf`
- `nginx/certs/fullchain.crt`
- `nginx/certs/private.key`

Pasos:

1. Copia `.env.docker.example` a `.env.docker`.
2. Completa secretos y datos de Entra ID.
3. Coloca certificados reales en `nginx/certs/`.
4. Levanta el stack:

```powershell
docker compose -f docker-compose.yml --env-file .env.docker up -d --build
```

Validacion minima:

```powershell
curl.exe -k -sS -i --max-time 10 https://localhost/health
curl.exe -k -sS -i --max-time 10 https://localhost/auth/health
curl.exe -k -sS -i --max-time 10 --max-redirs 0 https://localhost/auth/session
```

Resultado esperado:

- `https://localhost/health` -> `200 OK`
- `https://localhost/auth/health` -> `200 OK`
- `https://localhost/auth/session` sin sesion -> `302` a `/oauth2/start?...`

### 2. VM compartida con proxy frontal

Usa este modo cuando otra capa de infraestructura ya recibe `80/443` y este repo solo debe publicarse internamente.

Archivos clave:

- `docker-compose.vm-shared.yml`
- `nginx/conf/app.docker.shared.conf`

Pasos:

1. Copia `.env.docker.example` a `.env.docker`.
2. Completa secretos y datos de Entra ID.
3. Levanta el stack:

```powershell
docker compose -f docker-compose.vm-shared.yml --env-file .env.docker up -d --build
```

Validacion minima:

```powershell
curl.exe -sS -i --max-time 10 http://localhost:8081/health
curl.exe -sS -i --max-time 10 http://localhost:8081/auth/health
curl.exe -sS -i --max-time 10 --max-redirs 0 http://localhost:8081/auth/session
```

Resultado esperado:

- `http://localhost:8081/health` -> `200 OK`
- `http://localhost:8081/auth/health` -> `200 OK`
- `http://localhost:8081/auth/session` sin sesion -> `302` a `/oauth2/start?...`

## Operacion remota en la VM

Si trabajas por `VS Code Remote SSH`:

- Git corre en la VM
- `docker compose` corre en la VM
- logs, `exec`, `ps` y validaciones ocurren sobre el entorno real
- Codex debe abrirse en esa misma ventana remota para compartir contexto con el despliegue activo

Guia detallada:

- `docs/vm_remote_ssh.md`

## Integracion con otros servicios

Este servicio no se consume entrando al contenedor directamente. Se consume por su URL publicada o por el proxy frontal.

Casos de uso:

- navegador humano: entra por `https://e3display.com`
- otra aplicacion web: reutiliza el patron `auth_request`
- otro backend: consulta `/auth/session`, `/auth/me` o `/auth/groups` conservando cookies o headers del usuario
- infraestructura compartida: consume el upstream HTTP interno definido en la arquitectura

## Integracion con Folder API

Este repo puede proteger rutas humanas de `CreacionCarpetasM`:

- `GET /folders/create/browser`
- `POST /folders/create`
- `GET /folders/docs`
- `GET /folders/openapi.json`

En ese escenario:

- `folder-api` sigue siendo un servicio separado
- `nginx` exige sesion de usuario para las rutas humanas
- `nginx` reenvia `X-Authenticated-*` y `X-Internal-Proxy`
- `POST /folders/create/system` sigue fuera del flujo humano

## Documentacion complementaria

- `docs/vm_remote_ssh.md`
- `docs/arquitectura.md`
- `nginx/README.md`
- `services/auth_api/README.md`