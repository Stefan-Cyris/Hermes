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

## SSH Shell Setup and Coolify Environment Variables

The Hermes home directory is `/opt/data`. For initial shell setup, copy `.bashrc`
and `.profile` from `/etc/skel` into that directory. Run these commands inside the
Hermes container as the `hermes` user. Existing files are preserved as numbered
backups; merge any customizations from those backups afterward.

```bash
sudo cp --backup=numbered /etc/skel/.bashrc /opt/data/.bashrc
sudo cp --backup=numbered /etc/skel/.profile /opt/data/.profile
sudo chown hermes:hermes /opt/data/.bashrc /opt/data/.profile
```

Coolify injects container environment variables into PID 1, but SSH login shells
do not automatically inherit them. Append the following Bash snippet to
`/opt/data/.bashrc`, after its existing contents. The Ubuntu `.profile` sources
`.bashrc` for Bash login shells.

```bash
# Container env (set in Coolify) on PID 1; SSH login shells don't inherit it.
# Imports every variable the shell doesn't already have, so PATH, HOME etc. stay the shell's own.
while IFS= read -r -d '' kv; do
    name=${kv%%=*}
    [[ $name =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue
    [[ -n ${!name+x} ]] || export "$kv"
done < <(sudo -n cat /proc/1/environ 2>/dev/null)
unset kv name
```

This uses the container's existing passwordless sudo configuration to read PID 1's
environment. Add the snippet once; do not put it directly in `.profile`, since it
uses Bash-specific syntax. Apply it to the current Bash shell with:

```bash
source /opt/data/.bashrc
```

The shell files persist in the `hermes-data` volume. After changing Coolify
environment variables, redeploy the container and open a new SSH session to load
the updated values. Existing shell variables, including empty ones, are not
overwritten by this snippet.

## Troubleshooting: Container Keeps Restarting

If the Hermes container keeps restarting, check its logs for a Tailscale
authentication error, such as `invalid key: API key does not exist`. A missing,
expired, revoked, or already-used one-off Tailscale auth key can prevent startup.
The startup script exits when `tailscale up` fails, causing the container to restart.

Generate a new **auth key** (not an API access token) at
[Tailscale Admin Console → Keys](https://login.tailscale.com/admin/settings/keys).
Choose **Reusable** for this setup, replace `TS_AUTHKEY` in the Hermes resource's
Coolify environment variables with the complete key, then save and redeploy.
Do not commit the key to this repository.

If `TS_AUTHKEY` is missing entirely, Compose may reject the deployment before the
container starts. If the logs show a different error, investigate that error
rather than assuming the key is the cause.
