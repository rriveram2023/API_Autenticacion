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
