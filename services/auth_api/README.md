# API de autenticacion

Servicio FastAPI responsable de exponer sesion, identidad y grupos para el frente de autenticacion.

## Responsabilidades

- redirigir login y callback hacia `oauth2-proxy`
- exponer estado general y salud de AD
- traducir headers internos del proxy a un contexto de usuario reutilizable
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
- `GET /auth/docs`