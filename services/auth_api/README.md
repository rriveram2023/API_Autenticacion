# API de autenticacion

Servicio FastAPI responsable de exponer sesion, identidad y grupos para el frente HTTPS de autenticacion.

## Responsabilidades

- redirigir el login hacia `oauth2-proxy`
- conservar `GET /auth/callback` como endpoint de compatibilidad
- exponer estado general y salud de AD
- traducir headers internos del proxy a un contexto de usuario reutilizable
- normalizar un username corporativo limpio a partir de `preferred_username`, correo o AD
- enriquecer identidad y grupos desde Active Directory cuando falte informacion en los headers

## Punto de entrada

- `services/auth_api/app.py`

## Endpoints

- `GET /health`
- `GET /auth/health`
- `GET /auth/ad-health`
- `GET /auth/login`
- `GET /auth/callback`
- `POST /auth/logout`
- `GET /auth/session`
- `GET /auth/me`
- `GET /auth/groups`
- `GET /auth/proxy-identity` (interno para `nginx` en `443`)
- `GET /auth/docs`

## Notas operativas

- el callback oficial del listener `4441` es `GET /oauth2/callback`
- `GET /auth/callback` solo se mantiene por compatibilidad y no debe ser la Redirect URI principal en Entra ID para E3 OS
- el listener `4441` usa validacion de sesion por request con `auth_request /oauth2/auth`
- el enriquecimiento reusable via `GET /auth/proxy-identity` se mantiene para `443` y servicios ya publicados
