# TLS certs for direct HTTPS mode

Place only the real production certificate files here when using `docker-compose.yml`:

- `fullchain.crt`
- `private.key`

This folder is intentionally kept in the repo only as a placeholder.
The real certificate contents must stay local on the VM and must not be committed.

Use this folder only for the direct HTTPS stack.
For `docker-compose.vm-shared.yml`, TLS must stay in the shared front proxy and this folder is not used.