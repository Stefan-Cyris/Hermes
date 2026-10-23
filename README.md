# Hermes Remote Box

Standalone Hermes deployment for Coolify.

## Files

- `Dockerfile` builds the Hermes remote box image with Tailscale, SSH, Node, Python, uv, GitHub CLI, and Hermes runtime prerequisites.
- `.github/workflows/publish-image.yml` builds that image in GitHub Actions and publishes it to GHCR.
- `docker-compose.yml` pulls the published Hermes image and starts it with a PostgreSQL 17 pgvector sidecar. Coolify does not build the image.

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

Use the existing Hermes Docker Compose resource in Coolify with these settings:

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

### GHCR image and rollout

This follows Zwistory's deployment pattern: GitHub Actions builds a Linux ARM64
image on a native ARM runner for the Coolify host. Each push to `main` publishes
`ghcr.io/stefan-cyris/hermes:main` and `ghcr.io/stefan-cyris/hermes:sha-<full-commit-sha>`.
The workflow can also be started manually. A manual run on another branch only
publishes its SHA tag and does not replace `:main`.

The registry build cache reuses unchanged Dockerfile layers between workflow runs.
The first build populates the cache and still takes the full build time. GitHub
Actions uses its built-in `GITHUB_TOKEN` with `packages: write`; no additional
personal token is needed in this repository.

For the first rollout and subsequent image updates:

1. Push the changes to `main` and wait for **Publish image** in GitHub Actions to
   finish successfully before pressing **Deploy** in Coolify.
2. Refresh the existing resource's Compose configuration from `docker-compose.yml`.
   If Coolify stores the Compose file directly, paste the updated file there.
   Keep the same resource and its existing volumes to retain Hermes, Tailscale,
   and PostgreSQL data.
3. Reuse the GHCR login already configured for Zwistory on the deployment server.
   Its token must have `read:packages` access to the new **hermes** package too.
   Keep registry credentials out of the Compose environment and repository.
4. Disable any Git-push auto-deploy for this resource so Coolify does not deploy
   before the image has been published. Deploy manually after the workflow is green,
   as with Zwistory.
5. Press **Deploy**. The Hermes service has no `build:` section, and
   `pull_policy: always` fetches the current image on each deployment.

There is no need to recreate the resource or switch it to a single-image app:
the PostgreSQL sidecar stays in the same Compose stack. After the initial update,
refresh the Compose configuration only when that file changes.

Optionally set `HERMES_IMAGE` in Coolify to an existing SHA tag for a rollback or
test deployment:

```env
HERMES_IMAGE=ghcr.io/stefan-cyris/hermes:sha-<full-commit-sha>
```

Leave `HERMES_IMAGE` unset to follow `:main`. The published image targets ARM64,
like Zwistory; it is not a native AMD64 image.

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

## Using an External PostgreSQL Server

You can use an existing PostgreSQL server instead of the bundled sidecar. The
server must have pgvector installed for its PostgreSQL version; for a separate
Coolify database, `pgvector/pgvector:pg17` already includes it. A standard PostgreSQL
image does not include pgvector automatically. The database host must be reachable
from the Hermes container, with network/firewall and `pg_hba.conf` rules allowing
the connection. For separate Coolify resources, attach them to a shared Docker
network and use the database's hostname on that network.

### Create the role, database, and extension

Connect to the external server's `postgres` database as an administrator using
`psql`, for example from its Coolify terminal. For a remote connection, replace
the hostname and administrator name and use the server's TLS settings:

```bash
psql "host=postgres.internal port=5432 dbname=postgres user=postgres sslmode=require" -W
```

Run the following once for a **new** role and database. The backslash commands are
`psql` commands; in a graphical SQL editor, set the role's password and reconnect
to the `hermes` database separately. Do not wrap `CREATE DATABASE` in a transaction.

```sql
\set ON_ERROR_STOP on

CREATE ROLE hermes WITH LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION;
\password hermes

CREATE DATABASE hermes OWNER hermes;
GRANT CONNECT, TEMPORARY ON DATABASE hermes TO hermes;

\connect hermes

CREATE EXTENSION IF NOT EXISTS vector WITH SCHEMA public;
GRANT USAGE, CREATE ON SCHEMA public TO hermes;

SELECT extname, extversion FROM pg_extension WHERE extname = 'vector';
```

`\password` prompts for the new role's password. Enable the extension as the
administrator **in the target database**; installing pgvector on the server is
not enough. On managed PostgreSQL, use the provider's extension-enabled admin
role. The Hermes role does not need superuser privileges.

Hermes owns this database and must create its application tables and indexes as
`hermes`. It then owns those objects and can migrate them without additional
table or sequence grants. Database grants alone do not grant access to tables
created by another role: when importing existing data, preserve or explicitly
assign the application objects' ownership to `hermes`.

### Point the Compose resource at the external database

The repository's default Compose file still uses the local sidecar. In the
existing Coolify resource's Compose configuration:

1. Remove the `postgres` service and the Hermes service's `depends_on` block.
2. Remove the now-unused top-level `hermes-postgres-data` volume declaration.
   Keep `hermes-data` and `hermes-tailscale-state`. Do not delete the old database
   volume if it contains data you still need; this setup does not migrate data.
3. Replace these three entries under `services.hermes.environment`, keeping the
   other environment entries:

```yaml
HERMES_POSTGRES_HOST: ${HERMES_POSTGRES_HOST:?set HERMES_POSTGRES_HOST}
HERMES_POSTGRES_PORT: ${HERMES_POSTGRES_PORT:-5432}
HERMES_DATABASE_URL: ${HERMES_DATABASE_URL:?set HERMES_DATABASE_URL}
```

Set the matching runtime variables in Coolify, using the password entered above:

```env
HERMES_POSTGRES_HOST=postgres.internal
HERMES_POSTGRES_PORT=5432
HERMES_POSTGRES_USER=hermes
HERMES_POSTGRES_PASSWORD=<raw-password>
HERMES_POSTGRES_DB=hermes
HERMES_DATABASE_URL=postgresql://hermes:<url-encoded-password>@postgres.internal:5432/hermes?sslmode=require
```

The host, port, user, password, and database in the URL must match the individual
variables. Percent-encode special characters in the URL's password (for example,
`@` becomes `%40`); keep the separate password variable unencoded. Use the
provider's TLS settings, including a CA certificate when required. Save and
redeploy, then open a new SSH session if using the shell environment import below.

### Verify access as the Hermes role

Connect from a client on the same network as Hermes, using the application's role:

```bash
psql "host=postgres.internal port=5432 dbname=hermes user=hermes sslmode=require" -W
```

Run this check in that session. It verifies table/index creation, sequence use,
and vector operations, and rolls back the test objects:

```sql
\set ON_ERROR_STOP on
SELECT current_user, current_database();
SELECT extname, extversion FROM pg_extension WHERE extname = 'vector';

BEGIN;
CREATE TABLE public.hermes_pgvector_check (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    embedding public.vector(3)
);
INSERT INTO public.hermes_pgvector_check (embedding) VALUES ('[1,2,3]');
SELECT id, embedding <-> '[1,2,3]'::public.vector AS distance
FROM public.hermes_pgvector_check;
ROLLBACK;
```

The role and database should both be `hermes`, the extension query should return
a version, and the vector distance should be `0`. If a statement fails, run
`ROLLBACK;` before retrying.

References: [PostgreSQL role creation](https://www.postgresql.org/docs/17/sql-createrole.html),
[database creation](https://www.postgresql.org/docs/17/sql-createdatabase.html),
[privileges](https://www.postgresql.org/docs/17/sql-grant.html), and
[pgvector installation and usage](https://github.com/pgvector/pgvector).

## Local Start

On an ARM64 Docker host with GHCR access, after the first image has been published:

```powershell
docker compose up -d
docker compose logs -f hermes
```

For a local image build on your own architecture, the Dockerfile remains available:

```powershell
docker build -t hermes-prod:local .
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
