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
