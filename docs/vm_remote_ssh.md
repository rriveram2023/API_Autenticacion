# Acceso remoto a la VM con VS Code

## Objetivo

Trabajar directamente sobre la VM donde vive el despliegue real para que:

- Git corra en la VM
- Docker corra en la VM
- VS Code abra la carpeta real del despliegue
- Codex use ese mismo workspace remoto

## Ruta real del proyecto

```text
C:\Apps\Autenticacion\API_Autenticacion
```

## Operacion diaria en la VM

El unico compose soportado es `docker-compose.yml`.

Levantar o actualizar:

```powershell
cd C:\Apps\Autenticacion\API_Autenticacion
docker compose -f docker-compose.yml --env-file .env.docker up -d --build
```

Ver estado:

```powershell
docker compose -f docker-compose.yml --env-file .env.docker ps
```

Ver logs:

```powershell
docker compose -f docker-compose.yml --env-file .env.docker logs -f nginx
docker compose -f docker-compose.yml --env-file .env.docker logs -f oauth2-proxy
docker compose -f docker-compose.yml --env-file .env.docker logs -f auth-api
```

Recargar solo nginx despues de cambios de configuracion:

```powershell
docker exec api-autenticacion-nginx nginx -t
docker exec api-autenticacion-nginx nginx -s reload
```

## Validacion remota minima

```powershell
cd C:\Apps\Autenticacion\API_Autenticacion
docker compose -f docker-compose.yml --env-file .env.docker config --quiet
docker exec api-autenticacion-nginx nginx -t
curl.exe -k -sS -i --max-time 10 https://localhost/health
curl.exe -k -sS -i --max-time 10 https://localhost/auth/health
curl.exe -k -sS -i --max-time 10 --max-redirs 0 https://localhost:4441/
```

Criterio esperado:

- `GET /health` responde `200 OK`
- `GET /auth/health` responde `200 OK`
- `GET /` en `4441` sin sesion responde `302` a `/oauth2/start?...`
- despues de autenticacion, los logs deben mostrar `GET /oauth2/auth -> 202`

## Callback correcto para `4441`

La Redirect URI correcta en Entra ID es:

```text
https://e3display.com:4441/oauth2/callback
```

No uses `https://e3display.com/auth/callback` como URI principal para el listener `4441`.

## Certificados

Este repo termina TLS por si mismo, asi que los certificados reales deben existir en:

```text
C:\Apps\Autenticacion\API_Autenticacion\nginx\certs\fullchain.crt
C:\Apps\Autenticacion\API_Autenticacion\nginx\certs\private.key
```

Esos archivos no deben subirse a Git.
