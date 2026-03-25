# Servicio de Login y Folder API

Este `nginx` ahora publica dos servicios separados:

- `Auth API`: login, callback, sesion, identidad y grupos
- `Folder API`: creacion de carpetas y endpoint tecnico para automatizacion

Los dos servicios ya quedaron fisicamente separados para poder moverse a repositorios Git distintos:

- `services/auth_api`
- `services/folder_api`

## Dominio y callback

El certificado y la redirect URI ya no usan `e3os.local`.

Valores objetivo:

- Hostname publico: `e3display.com`
- Redirect URI en Entra ID: `https://e3display.com/auth/callback`
- Certificado recomendado en disco:
  - `nginx/certs/e3display.com.cert`
  - `nginx/certs/e3display.com.pem`

## Arquitectura de runtime

- `oauth2-proxy`: autentica contra Microsoft Entra ID
- `nginx`: protege rutas y reenvia headers confiables
- `Auth API`: corre por defecto en `127.0.0.1:8001`
- `Folder API`: corre por defecto en `127.0.0.1:8002`

## Rutas publicadas

### Auth API

- `GET /auth/login`
- `GET /auth/callback`
- `POST /auth/logout`
- `GET /auth/session`
- `GET /auth/me`
- `GET /auth/groups`
- `GET /auth/health`
- `GET /auth/ad-health`
- `GET /auth/docs`

### Folder API

- `GET /folders/create/browser?cod_cliente=TST&proyecto=DEMO&id_proyecto=10002`
- `POST /folders/create`
- `POST /folders/create/system`
- `GET /folders/docs`
- `GET /health`

## Front door sin MFA

La variante sin MFA sigue siendo un segundo front door del mismo backend logico. Ya hay una plantilla para esa entrada en:

- [app_trusted_network.example.conf](/d:/Archivos_rriveram/Akira/Propuesta_carpetas/nginx/conf/app_trusted_network.example.conf)

Ese template ya separa `Auth API` y `Folder API` y marca `X-Auth-Mfa-Policy=trusted_network`.

## Variables relevantes en `.env`

- `AUTH_API_HOST`
- `AUTH_API_PORT`
- `FOLDER_API_HOST`
- `FOLDER_API_PORT`
- `NGINX_PUBLIC_HOST=e3display.com`
- `OAUTH2_PROXY_REDIRECT_URL=https://e3display.com/auth/callback`
- `TLS_CERT_PATH`
- `TLS_KEY_PATH`
- `SYSTEM_API_KEYS`
- `SQL_BRIDGE_API_URL=https://e3display.com`
- `SQL_BRIDGE_API_KEY`

## Separacion por repositorio

Si vas a dividir el proyecto en dos repos Git, la base ya esta preparada:

- repositorio 1: copiar `services/auth_api`
- repositorio 2: copiar `services/folder_api`

Cada carpeta ya tiene su propio:

- `README.md`
- `requirements.txt`
- punto de entrada `app.py`

Los archivos de raiz `main.py`, `auth_service.py` y `creacion_carpetas.py` quedaron solo como wrappers de compatibilidad para no romper el stack actual mientras validamos.

## SQL Server

La integracion con SQL Server sigue desacoplada:

- [folder_api_dispatch.sql](/d:/Archivos_rriveram/Akira/Propuesta_carpetas/sql/folder_api_dispatch.sql)
- [sql_bridge_folder_api.ps1](/d:/Archivos_rriveram/Akira/Propuesta_carpetas/scripts/sql_bridge_folder_api.ps1)

El trigger solo encola y el bridge llama `POST /folders/create/system` con `X-Api-Key`.

## Arranque de pruebas

1. Ajusta `.env` con `e3display.com`.
2. Coloca el `.cert` y `.pem` en `nginx/certs/`.
3. Registra en Entra ID la URI `https://e3display.com/auth/callback`.
4. Levanta el stack:

```powershell
.\nginx\start_stack_entra.ps1
```

5. Prueba:

```text
https://e3display.com/auth/docs
https://e3display.com/auth/me
https://e3display.com/folders/docs
https://e3display.com/folders/create/browser?cod_cliente=TST&proyecto=DEMO&id_proyecto=10002
```