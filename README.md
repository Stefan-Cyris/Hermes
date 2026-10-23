# Hermes Remote Box

Standalone Hermes deployment for Coolify.

## Files

- `Dockerfile` builds the Hermes remote box image with Tailscale, SSH, Node, Python, uv, GitHub CLI, and Hermes runtime prerequisites.
- `.github/workflows/publish-image.yml` builds that image in GitHub Actions and publishes it to GHCR.
- `docker-compose.yml` pulls the published Hermes image and starts it with a PostgreSQL 17 pgvector sidecar. Coolify does not build the image.
- `docker-compose.base.yml` starts only the Hermes box, using an external PostgreSQL server. It is a standalone alternative to `docker-compose.yml`.

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

For an external PostgreSQL server, set **Docker Compose Location** to
`/docker-compose.base.yml` instead; see the external database setup below.

Do not deploy this as a Nixpacks app on port 3000. Both variants run as a
Docker Compose application and pull the Hermes image from GHCR.

### GHCR image and rollout

This follows Zwistory's deployment pattern: GitHub Actions builds a Linux ARM64
image on a native ARM runner for the Coolify host. Pushes to `main` that change
`Dockerfile` or `.dockerignore` publish `ghcr.io/stefan-cyris/hermes:main` and
`ghcr.io/stefan-cyris/hermes:sha-<full-commit-sha>`.
Compose, README, and workflow-only changes do not automatically rebuild the image;
they reuse the last published image. Such commits do not get a new image SHA tag.
The workflow can also be started manually, for example after changing build flags
in the workflow. Manual runs still use the build cache. A manual run on another
branch only publishes its SHA tag and does not replace `:main`.

The registry build cache reuses unchanged Dockerfile layers between workflow runs.
The first build populates the cache and still takes the full build time. GitHub
Actions uses its built-in `GITHUB_TOKEN` with `packages: write`; no additional
personal token is needed in this repository.

For the first rollout and subsequent image updates:

1. Push the changes to `main`. If `Dockerfile` or `.dockerignore` changed, wait for
   **Publish image** in GitHub Actions to finish successfully before pressing
   **Deploy** in Coolify. Compose-only changes need no new image build. For the
   first deployment, ensure an image has been published; start the workflow manually
   if necessary.
2. Refresh the existing resource's Compose configuration using **Reload Compose**.
   Its **Docker Compose Location** selects `/docker-compose.yml` (with PostgreSQL)
   or `/docker-compose.base.yml` (external PostgreSQL). The editor is read-only for
   Git-based resources: change the file in the repository, then reload it in Coolify.
   Only resources created as **Docker Compose Empty** accept a pasted Compose file.
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

There is no need to recreate the resource or switch it to a single-image app.
The default file includes the PostgreSQL sidecar; the base file omits it.
After the initial update, refresh the Compose configuration when the selected
file changes.

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

Tailscale needs these container options. They are already defined in both
Compose files:

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

### Create the role, database, and extension in pgAdmin

The following blocks contain plain SQL for the **pgAdmin Query Tool**. Run each
block separately and continue only after it succeeds.

1. Connect to the external server as an administrator. In the object browser,
   right-click the existing **postgres** database and open **Query Tool**.
   Enable **Auto-commit** in the Query Tool. If a previous query left an open or
   failed transaction, finish it first; use `ROLLBACK;` to discard an unsuccessful
   setup attempt before proceeding.
2. Create the login role. Replace the password placeholder with a long, random
   password using letters, digits, `-`, `.`, `_`, and `~`, matching the generated
   connection URL described below:

```sql
CREATE ROLE hermes WITH
    LOGIN
    NOSUPERUSER
    NOCREATEDB
    NOCREATEROLE
    NOREPLICATION
    PASSWORD 'REPLACE_WITH_A_LONG_RANDOM_PASSWORD';
```

If the role already exists from an earlier attempt, skip `CREATE ROLE`. To set
its password, run this separately with the chosen password instead:

```sql
ALTER ROLE hermes WITH PASSWORD 'REPLACE_WITH_A_LONG_RANDOM_PASSWORD';
```

3. Still connected to **postgres**, run **only this statement** in its own
   execution. `CREATE DATABASE` must run with Auto-commit on, outside a transaction
   and without other SQL statements in the same execution:

```sql
CREATE DATABASE hermes OWNER hermes;
```

If the database already exists, skip creation and verify its owner in pgAdmin's
database properties. This walkthrough assumes `hermes` owns the database.

4. Refresh **Databases** in pgAdmin's object browser. Right-click the new
   **hermes** database and open a **new Query Tool** as the administrator. Creating
   a database does not switch an existing query tab's connection. First check:

```sql
SELECT current_database(), current_user;
```

The database must be `hermes`, and the user must still be the administrator.
Then enable pgvector and grant the application privileges **in this database**:

```sql
CREATE EXTENSION IF NOT EXISTS vector WITH SCHEMA public;
GRANT CONNECT, TEMPORARY ON DATABASE hermes TO hermes;
GRANT USAGE, CREATE ON SCHEMA public TO hermes;

SELECT extname, extversion FROM pg_extension WHERE extname = 'vector';
```

Installing pgvector on the server is not enough: enable the extension in each
target database. On managed PostgreSQL, use the provider's extension-enabled
admin role. The Hermes role does not need superuser privileges. If the extension
is unavailable, install pgvector for the server's PostgreSQL version first.

Hermes owns this database and must create its application tables and indexes as
`hermes`. It then owns those objects and can migrate them without additional
table or sequence grants. Database grants alone do not grant access to tables
created by another role: when importing existing data, preserve or explicitly
assign the application objects' ownership to `hermes`.

### Point the Compose resource at the external database

Use the ready-made `docker-compose.base.yml`. It contains only Hermes, with no
PostgreSQL service, database volume declaration, or local database dependency.
It reads the external connection details from Coolify's runtime variables.

In the **existing** Hermes resource, open **General → Build pipeline**, change
**Docker Compose Location** to `/docker-compose.base.yml`, save, and click
**Reload Compose**. Keep the Git source, branch, and base directory unchanged.
The Compose editor stays read-only because Git is the source of truth.

Keep the same resource so its `hermes-data` and `hermes-tailscale-state` volumes
retain their identity. Before deploying, check **Show Deployable Compose** or
**Persistent Storage** to confirm those mounts are unchanged. Do not delete the
old PostgreSQL volume if it contains data you still need; switching files does
not migrate database contents.

If PostgreSQL is another Coolify resource, enable **Advanced → Docker compose →
Predefined network → Connect to predefined network** for Hermes when needed to
reach that resource, and use its actual hostname on the shared network.

Set the matching runtime variables in Coolify, using the password entered above:

```env
HERMES_POSTGRES_HOST=postgres.internal
HERMES_POSTGRES_PORT=5432
HERMES_POSTGRES_USER=hermes
HERMES_POSTGRES_PASSWORD=<raw-password>
HERMES_POSTGRES_DB=hermes
```

These variables expose the connection details to tools in the container. The
startup script does not open a PostgreSQL connection or configure a database
integration automatically; configure each tool to use the settings it supports.
As in `docker-compose.yml`, Compose automatically assembles `HERMES_DATABASE_URL`
from host, port, user, password, and database and exposes it inside the container.
Do not set `HERMES_DATABASE_URL` separately in Coolify; remove an old manual entry
and use **Reload Compose** to load the updated definition.

Both Compose files interpolate credentials directly without URL encoding. Use
a long password consisting of URL-unreserved characters (letters, digits,
`-`, `.`, `_`, `~`) so the same value works as a raw password and in the generated
URL. Configure TLS using the consuming tool's supported settings and the
provider's requirements, including a CA certificate when needed. Save and redeploy,
then open a new SSH session if using the shell environment import below.

The base file requires `TS_AUTHKEY`, `HERMES_POSTGRES_HOST`, and
`HERMES_POSTGRES_PASSWORD`. Port defaults to `5432`, user and database to `hermes`.
Select only the base file; do not combine it with `docker-compose.yml`, because
Compose merges would retain the local database.

### Verify access as the Hermes role

In pgAdmin, open the Query Tool's connection dropdown and choose **New Connection**.
Select the same server and database **hermes**, but use **hermes** as the login
user with the application password, rather than the administrator. Use the
server's required TLS settings. The pgAdmin server must be able to reach the
database; its successful connection does not also prove Hermes's container has
network access.

Run this check in the new connection. It verifies table/index creation, sequence
use, and vector operations, and rolls back the test objects:

```sql
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
For connection switching and executing selected SQL, see the
[pgAdmin Query Tool documentation](https://www.pgadmin.org/docs/pgadmin4/latest/query_tool.html).

## Local Start

On an ARM64 Docker host with GHCR access, after the first image has been published:

```powershell
docker compose up -d
docker compose logs -f hermes
```

For the base variant, set the external database variables above and select it
explicitly:

```powershell
docker compose -f docker-compose.base.yml up -d
docker compose -f docker-compose.base.yml logs -f hermes
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
