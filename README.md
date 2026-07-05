# Hermes Remote Box

Standalone Hermes deployment for Coolify.

## Files

- `Dockerfile` builds the Hermes remote box image with Tailscale, SSH, Node, Python, uv, GitHub CLI, and Hermes runtime prerequisites.
- `docker-compose.yml` starts the Hermes box plus a PostgreSQL 17 pgvector sidecar.

## Required Environment

```env
TS_AUTHKEY=tskey-auth-...
TS_HOSTNAME=hermes
HERMES_POSTGRES_USER=hermes
HERMES_POSTGRES_PASSWORD=change-this-long-password
HERMES_POSTGRES_DB=hermes
HERMES_SSH_PORT=2222
# Optional, only for localhost OpenSSH fallback:
HERMES_SSH_PASSWORD=change-this-long-password
```

## Coolify Deployment

Create a new Docker Compose resource in Coolify and use these settings:

```text
Repository URL: https://github.com/Stefan-Cyris/Hermes
Branch: main
Build Pack: Docker Compose
Base Directory: /
Docker Compose Location: /docker-compose.yml
Is it a static site?: No
```

If Coolify expects the compose path without a leading slash, use:

```text
docker-compose.yml
```

Do not deploy this as a Nixpacks app on port 3000. This repository runs a
Docker Compose stack with the Hermes box and a PostgreSQL sidecar.

Required Coolify environment variables:

```env
TS_AUTHKEY=tskey-auth-...
TS_HOSTNAME=hermes
HERMES_POSTGRES_USER=hermes
HERMES_POSTGRES_PASSWORD=change-this-long-password
HERMES_POSTGRES_DB=hermes
HERMES_SSH_PORT=2222
```

Optional SSH password fallback:

```env
HERMES_SSH_PASSWORD=change-this-long-password
```

Tailscale needs these container options. They are already defined in
`docker-compose.yml`:

```text
--cap-add=NET_ADMIN --cap-add=NET_RAW --device=/dev/net/tun:/dev/net/tun --tmpfs=/run --tmpfs=/tmp
```

Only add them as custom Docker options in Coolify if your Coolify setup does
not apply the Compose `cap_add`, `devices`, or `tmpfs` settings.

## Local Start

```powershell
docker compose up -d --build
docker compose logs -f hermes
```

## First Login

Connect over Tailscale SSH, or use the localhost fallback:

```powershell
ssh hermes@127.0.0.1 -p 2222
```

Install Hermes as the `hermes` user:

```bash
curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash
```
