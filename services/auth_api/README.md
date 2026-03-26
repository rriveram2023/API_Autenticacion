# Auth API

Servicio FastAPI para autenticacion, sesion, identidad y grupos.

Incluye:

- login y callback con Entra ID por medio de `oauth2-proxy`
- introspeccion de sesion
- identidad del usuario actual
- lectura de grupos y enriquecimiento opcional desde AD

Punto de entrada:

- `services/auth_api/app.py`

Endpoints:

- `GET /auth/login`
- `GET /auth/callback`
- `POST /auth/logout`
- `GET /auth/session`
- `GET /auth/me`
- `GET /auth/groups`
- `GET /auth/health`
- `GET /auth/ad-health`
- `GET /auth/docs`
