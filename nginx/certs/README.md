# Certificados TLS para HTTPS directo

Usa esta carpeta solo cuando el repo termina TLS por si mismo con `docker-compose.yml`.

Archivos esperados:

- `fullchain.crt`
- `private.key`

Esta carpeta queda en el repo solo como placeholder.
El contenido real de los certificados debe permanecer local en la VM y no debe versionarse.

Si usas `docker-compose.vm-shared.yml`, TLS vive en el proxy frontal compartido y esta carpeta no participa en el arranque.