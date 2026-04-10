# API_Autenticacion

Servicio de autenticacion para `e3display.com` basado en `FastAPI`, `oauth2-proxy` y `nginx`.

Este repo publica el frente HTTPS real del servicio y protege aplicaciones humanas adicionales mediante headers internos confiables reenviados por `nginx`.

## Modo soportado

El unico modo soportado por este repo es HTTPS directo en la misma VM con `docker-compose.yml`:

- `443` para `https://e3display.com/`
- `4441` para `https://e3display.com:4441/`
- callback OAuth2 directo en `https://e3display.com:4441/oauth2/callback`

La antigua variante `vm-shared` y sus puertos internos ya no forman parte del despliegue soportado.

## Componentes principales

- `services/auth_api/app.py`: API principal y endpoints `/auth/*`
- `services/auth_api/identity.py`: validacion de headers internos y enriquecimiento opcional desde AD
- `docker-compose.yml`: despliegue Docker soportado
- `nginx/conf/app.docker.conf`: `nginx` del despliegue real
- `nginx/conf/app.conf`: variante local sin Docker
- `docs/vm_remote_ssh.md`: operacion remota desde VS Code en la VM
- `docs/arquitectura.md`: arquitectura soportada

## Flujo de autenticacion

1. El usuario entra por `https://e3display.com` o `https://e3display.com:4441`.
2. `nginx` valida sesion con `auth_request` hacia `oauth2-proxy`.
3. Si no hay sesion, `nginx` redirige a `/oauth2/start` conservando `scheme`, `host`, `puerto` y `request_uri`.
4. `oauth2-proxy` autentica contra Microsoft Entra ID.
5. En `443`, `nginx` completa identidad mediante `/_auth/proxy-identity` y reenvia headers normalizados.
6. En `4441`, `nginx` usa el mismo subrequest reusable `/_auth/proxy-identity` para completar identidad y reenvia los headers `X-Authenticated-*` al backend final.

Headers internos hacia backends protegidos:

- `X-Authenticated-User`: username corporativo limpio
- `X-Authenticated-Email`
- `X-Authenticated-Groups`
- `X-Authenticated-Display-Name`
- `X-Auth-Mfa-Policy`
- `X-Internal-Proxy`

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
- `OAUTH2_PROXY_REDIRECT_URL=https://e3display.com:4441/oauth2/callback`
- `OAUTH2_PROXY_WHITELIST_DOMAINS=e3display.com:*`

Headers internos:

- `IDENTITY_HEADER`
- `IDENTITY_EMAIL_HEADER`
- `IDENTITY_GROUPS_HEADER`
- `IDENTITY_DISPLAY_NAME_HEADER`
- `MFA_POLICY_HEADER`
- `UPSTREAM_USER_HEADER`
- `UPSTREAM_PREFERRED_USERNAME_HEADER`
- `UPSTREAM_EMAIL_HEADER`
- `UPSTREAM_GROUPS_HEADER`
- `IDENTITY_USERNAME_SOURCE_ORDER`

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

## Despliegue soportado

1. Copia `.env.docker.example` a `.env.docker`.
2. Completa secretos y datos de Entra ID.
3. Coloca certificados reales en `nginx/certs/`.
4. Levanta o actualiza el stack:

```powershell
docker compose -f docker-compose.yml --env-file .env.docker up -d --build
```

## Validacion minima

```powershell
docker compose -f docker-compose.yml --env-file .env.docker config --quiet
docker exec api-autenticacion-nginx nginx -t
curl.exe -k -sS -i --max-time 10 https://localhost/health
curl.exe -k -sS -i --max-time 10 https://localhost/auth/health
curl.exe -k -sS -i --max-time 10 --max-redirs 0 https://localhost:4441/
```

Resultado esperado:

- `https://localhost/health` -> `200 OK`
- `https://localhost/auth/health` -> `200 OK`
- `https://localhost:4441/` sin sesion -> `302` a `/oauth2/start?...`
- despues de login, `oauth2-proxy` debe registrar `GET /oauth2/auth -> 202`

## Listener `4441` para E3 OS

`4441` queda reservado para aplicaciones humanas completas que no deben vivir bajo subpath.

Configuracion actual:

- servicio logico: `e3os_entraid`
- URL publicada: `https://e3display.com:4441/`
- callback OAuth2: `https://e3display.com:4441/oauth2/callback`
- backend Docker endurecido: `192.168.2.31:5001`
- backend local sin Docker: `127.0.0.1:5001`

Notas importantes:

- `4441` valida sesion en cada request usando `auth_request /_auth/proxy-identity`
- `4441` conserva `Host` y `X-Forwarded-Host` con puerto incluido porque el flujo real depende de `:4441`
- el loop `/menu -> /auth/login` pertenece a E3 OS, no a este stack

## Integracion con otros servicios

- `443` y `4441` mantienen el flujo reusable basado en `/_auth/proxy-identity`
- `Folder API` sigue protegido en `443`
- futuros servicios humanos completos deben usar un listener dedicado como `4441`

## Documentacion complementaria

- `docs/vm_remote_ssh.md`
- `docs/arquitectura.md`
- `nginx/README.md`
- `services/auth_api/README.md`
