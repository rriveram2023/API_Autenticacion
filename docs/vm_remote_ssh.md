# Acceso remoto a la VM con VS Code

## Objetivo

Trabajar directamente sobre la VM donde vive el despliegue para que:

- Git corra en la VM
- Docker corra en la VM
- VS Code abra la carpeta real del despliegue
- Codex use ese mismo workspace remoto

## Preparacion de la VM

En la VM Windows Server instala o habilita:

- Git
- Docker Desktop o el engine de contenedores que vayas a operar
- OpenSSH Server

Si `OpenSSH Server` no esta instalado, intenta:

```powershell
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
```

Verifica que el servicio SSH quede arriba:

```powershell
Get-Service sshd
Start-Service sshd
Set-Service -Name sshd -StartupType Automatic
```

Abre el puerto `22` en el firewall si aplica:

```powershell
New-NetFirewallRule -Name sshd -DisplayName "OpenSSH Server" -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22
```

## Estructura recomendada en la VM

Usa una ruta fija y facil de recordar:

```text
D:\Repos\API_Autenticacion
```

Si el proxy frontal comun guarda certificados u otros artefactos propios, mantenlos fuera del repo, por ejemplo:

```text
D:\Infra\
```

## Clonar el repositorio en la VM

Conectate por RDP o consola a la VM la primera vez y ejecuta:

```powershell
cd D:\
mkdir Repos -ErrorAction SilentlyContinue
cd D:\Repos
git clone https://github.com/rriveram2023/API_Autenticacion.git
cd .\API_Autenticacion
Copy-Item .env.docker.example .env.docker
```

Despues completa `.env.docker` con los secretos reales del ambiente.

## Conectar desde VS Code

En tu equipo local:

1. Instala la extension `Remote - SSH`.
2. Abre la paleta de comandos.
3. Ejecuta `Remote-SSH: Add New SSH Host`.
4. Agrega una entrada como esta:

```text
Host vm-auth
    HostName <ip-o-dns-de-la-vm>
    User <tu-usuario>
```

5. Ejecuta `Remote-SSH: Connect to Host...`
6. Elige `vm-auth`
7. Abre la carpeta:

```text
D:\Repos\API_Autenticacion
```

## Como trabajar luego con Codex

Una vez abierta la carpeta remota:

- usa esa ventana remota de VS Code para editar
- abre Codex en esa misma ventana
- ejecuta `docker compose`, `git`, logs y validaciones desde esa ventana remota

Asi Codex ve:

- el repo real de la VM
- los archivos `.env.docker` de ese ambiente
- el estado real de los contenedores
- los logs y puertos del servidor verdadero

## Operacion diaria en la VM

Levantar:

```powershell
docker compose -f docker-compose.vm-shared.yml --env-file .env.docker up -d --build
```

Ver estado:

```powershell
docker compose -f docker-compose.vm-shared.yml ps
```

Ver logs:

```powershell
docker compose -f docker-compose.vm-shared.yml logs -f nginx
docker compose -f docker-compose.vm-shared.yml logs -f oauth2-proxy
docker compose -f docker-compose.vm-shared.yml logs -f auth-api
```

Actualizar a la ultima version del repo:

```powershell
cd D:\Repos\API_Autenticacion
git pull origin main
docker compose -f docker-compose.vm-shared.yml --env-file .env.docker up -d --build
```

## Validacion remota del stack compartido

Una vez levantado el compose recomendado para VM compartida, valida desde la misma sesion remota:

```powershell
curl.exe -sS -i --max-time 10 http://localhost:8081/health
curl.exe -sS -i --max-time 10 http://localhost:8081/auth/health
curl.exe -sS -i --max-time 10 --max-redirs 0 http://localhost:8081/auth/session
docker compose -f docker-compose.vm-shared.yml --env-file .env.docker logs --tail 50 nginx oauth2-proxy auth-api
```

Criterio de exito esperado:

- `GET /health` responde `200 OK`
- `GET /auth/health` responde `200 OK`
- `GET /auth/session` sin sesion responde `302` hacia `/oauth2/start?...`
- los logs muestran:
  - `nginx` publicando en `8081`
  - `oauth2-proxy` respondiendo `401` en `/oauth2/auth` para usuarios sin sesion
  - `auth-api` respondiendo `200` en `/health` y `/auth/health`

## TLS y certificados en la VM compartida

Para la variante `docker-compose.vm-shared.yml` recomendada en produccion compartida:

- no copies `key`, `pem` ni certificados dentro de este repo
- no montes certificados dentro de los contenedores de este stack
- el TLS debe vivir en el proxy frontal compartido de la VM o de la infraestructura
- este stack solo debe recibir trafico HTTP interno, por ejemplo `http://<host-vm>:8081`

Solo si cambias a la variante con TLS dentro del stack (`docker-compose.yml`):

- coloca los archivos de certificado en `nginx/certs/`
- el contenedor `nginx` los monta en `/etc/nginx/certs`
- el contenedor `auth-api` los monta en `/run/certs`
- manten esos archivos fuera de Git

Regla practica:

- VM compartida en produccion: certificados fuera del repo y fuera de este compose
- VM dedicada o laboratorio con TLS interno: certificados en `nginx/certs/` para el compose con `443`
