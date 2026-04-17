# How Do I Deploy CoreMatrix?

This document describes the current supported self-host path for CoreMatrix.

Current deployment model:

- Linux host with Docker and Docker Compose plugin
- PostgreSQL 18 in Docker
- CoreMatrix split into `migrator`, `app`, and `jobs`
- explicit host bind mounts for all durable service data
- operator setup through `cmctl`

Current distribution reality:

- published images are not available yet
- the practical deployment path is to sync the local `core_matrix/` working
  tree to the target host with `rsync`, then build on the host

That makes this a production-like deployment procedure, not a polished
installer yet.

This guide describes the local-build Compose path. If CoreMatrix later ships a
registry-backed deployment, treat that as a separate Compose variant instead of
overloading the current file.

## What Is Supported Today

Treat this as the supported path today:

1. Deploy CoreMatrix only.
2. Run it in the production Compose topology from
   [compose.yaml.sample](/Users/jasl/Workspaces/Ruby/cybros/core_matrix/compose.yaml.sample).
3. Bootstrap it with
   [core_matrix_cli](/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli).
4. Add external agents and channel integrations later.

Do not treat the repository root as the deployment entrypoint. The old root
Compose stack was removed because it no longer matched the production shape.

## Host Requirements

- 64-bit Linux host
- Docker Engine with Compose plugin
- enough disk for PostgreSQL, Rails assets, and uploaded files
- SSH access
- either:
  - a private LAN address for operator access, or
  - a public HTTPS edge if you need webhook integrations

ARM64 and AMD64 hosts are both acceptable.

## Choose Your Network Mode

### Private LAN bootstrap

Use this first if the machine is at home or in an office and no external
service needs to call back into CoreMatrix yet.

Example:

```env
CORE_MATRIX_PUBLIC_BASE_URL=http://10.0.0.116:3000
RAILS_FORCE_SSL=false
RAILS_ASSUME_SSL=false
```

This is enough for:

- browser access
- `cmctl`
- Codex device flow
- Telegram polling

It is not enough for Telegram webhook.

### Private HTTPS on the LAN

Use this when you add an internal reverse proxy and a trusted internal DNS
name.

Example:

```env
CORE_MATRIX_PUBLIC_BASE_URL=https://corematrix.home.arpa
RAILS_FORCE_SSL=true
RAILS_ASSUME_SSL=true
```

### Public HTTPS edge

Use this only when you need webhook integrations or remote internet access.

Example:

```env
CORE_MATRIX_PUBLIC_BASE_URL=https://core.example.com
RAILS_FORCE_SSL=true
RAILS_ASSUME_SSL=true
```

## Files That Matter

Start from:

- [env.sample](/Users/jasl/Workspaces/Ruby/cybros/core_matrix/env.sample)
- [compose.yaml.sample](/Users/jasl/Workspaces/Ruby/cybros/core_matrix/compose.yaml.sample)

The minimum deployment files on the host are:

- `core_matrix/.env`
- `core_matrix/compose.yaml`
- `core_matrix/shared/postgres`
- `core_matrix/shared/storage`
- optional `core_matrix/config.d/*`

## Step 1: Sync The Code To The Host

Until images are published, sync the local source tree to the target host.

Example:

```bash
rsync -az --delete \
  --exclude='.env' \
  --exclude='log' \
  --exclude='tmp' \
  --exclude='storage' \
  --exclude='coverage' \
  --exclude='node_modules' \
  --exclude='vendor/bundle' \
  /path/to/cybros/core_matrix/ \
  user@host:/home/jasl/cybros/core_matrix/
```

If you also want to run `cmctl` directly on the host, sync
`core_matrix_cli/` too:

```bash
rsync -az --delete \
  /path/to/cybros/core_matrix_cli/ \
  user@host:/home/jasl/cybros/core_matrix_cli/
```

Keep the synced host path stable. The rest of this guide assumes:

```text
/home/jasl/cybros/core_matrix
```

That path is an example working location, not a product requirement. Adjust it
if your host uses a different writable deployment root.

## Step 2: Create `.env`

Copy the sample and fill in real values:

```bash
cd /home/jasl/cybros/core_matrix
cp env.sample .env
```

Required values:

- `POSTGRES_PASSWORD`
- `RAILS_MASTER_KEY`
- `SECRET_KEY_BASE`
- `ACTIVE_RECORD_ENCRYPTION__PRIMARY_KEY`
- `ACTIVE_RECORD_ENCRYPTION__DETERMINISTIC_KEY`
- `ACTIVE_RECORD_ENCRYPTION__KEY_DERIVATION_SALT`

Recommended baseline for a private LAN bootstrap:

```env
CORE_MATRIX_PUBLIC_BASE_URL=http://10.0.0.116:3000
RAILS_FORCE_SSL=false
RAILS_ASSUME_SSL=false
RAILS_LOG_LEVEL=info
RAILS_MAX_THREADS=8
RAILS_WEB_CONCURRENCY=2
RAILS_PRIMARY_DB_POOL=16
RAILS_QUEUE_DB_POOL=48
RAILS_CABLE_DB_POOL=16
```

Notes:

- `RAILS_MASTER_KEY` should come from
  [config/master.key](/Users/jasl/Workspaces/Ruby/cybros/core_matrix/config/master.key)
  unless you intentionally rotate credentials for this installation
- generate fresh `SECRET_KEY_BASE` and Active Record encryption keys for a new
  installation unless you are deliberately preserving an existing install
- keep `CORE_MATRIX_PUBLIC_BASE_URL` as the operator-facing URL, not
  `http://core_matrix:80`

## Step 3: Create `compose.yaml`

Start from the checked-in sample:

```bash
cp compose.yaml.sample compose.yaml
mkdir -p config.d shared/postgres shared/storage
chown -R 1000:1000 shared/storage
```

`compose.yaml.sample` intentionally uses host bind mounts instead of
Docker-managed named volumes:

- `./shared/postgres` stores the PostgreSQL state root
- `./shared/storage` stores Active Storage blobs and derived files

That makes the installation easier to inspect, back up, and migrate in the
same way operators expect from products such as Discourse or GitLab, where
host-persistent data lives in an explicit shared directory tree.

`shared/storage` must be writable by the app container user. The shipped image
runs Rails as UID `1000`, so the example above pre-creates the directory with
matching ownership.

For early LAN bootstrap, a direct published port is fine:

```yaml
ports:
  - "3000:80"
```

Once a host reverse proxy exists, prefer loopback-only publication instead:

```yaml
ports:
  - "127.0.0.1:8080:80"
```

## Step 4: Validate The Compose Model

Run:

```bash
docker compose config >/tmp/core_matrix.compose.resolved.yml
```

The deployment should resolve to these services:

- `db`
- `migrator`
- `app`
- `jobs`

## Step 5: Build And Start CoreMatrix

Run:

```bash
docker compose up -d --build
```

Expected steady state:

- `db` healthy
- `migrator` completed successfully and stopped
- `app` healthy
- `jobs` running

Check:

```bash
docker compose ps
docker compose logs --tail=80 app jobs migrator
```

## Backup And Migration Boundary

The supported durable state for a single-host CoreMatrix deployment is:

- `shared/postgres`
- `shared/storage`
- `.env`
- `compose.yaml`
- optional `config.d/*`

Those paths should be included in host-level backup, snapshot, and migration
procedures.

For a coarse offline backup on a small installation:

```bash
docker compose down
tar -C /home/jasl/cybros/core_matrix -czf /tmp/core_matrix-state.tgz \
  shared/postgres shared/storage .env compose.yaml config.d
docker compose up -d
```

For PostgreSQL-aware backup, prefer adding a regular `pg_dump` or physical
base-backup flow on top of the filesystem-level copy.

## Step 6: Verify Health

From the host:

```bash
curl -fsS http://127.0.0.1:3000/up
curl -fsS http://127.0.0.1:3000/app_api/bootstrap/status
```

Before bootstrap, the second command should report:

```json
{"bootstrap_state":"unbootstrapped"}
```

The `jobs` logs should show Solid Queue workers plus the recurring scheduler.
For Telegram polling, this recurring scheduler is required.

## Step 7: Bootstrap The Installation

Use
[core_matrix_cli](/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli) from
either:

- your laptop on the same LAN, using the LAN URL
- the server itself, using `http://127.0.0.1:3000`

Example on the host:

```bash
cd /home/jasl/cybros/core_matrix_cli
bundle install
bundle exec exe/cmctl init
```

The first operator flow asks for:

- CoreMatrix base URL
- installation name
- operator email
- password
- display name

Then verify:

```bash
bundle exec exe/cmctl status
bundle exec exe/cmctl auth whoami
```

## Step 8: Create A Workspace

Current CoreMatrix bootstrap does not automatically create a workspace.

Run:

```bash
bundle exec exe/cmctl workspace create --name "Staging" --default
bundle exec exe/cmctl status
```

At this point it is normal for `selected workspace agent` to remain missing.
That requires a separately deployed agent such as Fenix.

## Telegram Guidance

For private-LAN deployments, start with polling:

```bash
bundle exec exe/cmctl ingress telegram setup
```

Do not attempt Telegram webhook until you have a public HTTPS entrypoint.

For more details, use
[INTEGRATIONS.md](/Users/jasl/Workspaces/Ruby/cybros/core_matrix/docs/INTEGRATIONS.md).

## Resetting A Broken Deployment

If you intentionally want to wipe the current CoreMatrix deployment on a host,
the destructive reset is:

```bash
cd /home/jasl/cybros/core_matrix
docker compose down -v --remove-orphans
docker image rm cybros_core_matrix-app cybros_core_matrix-jobs 2>/dev/null || true
```

Then remove and recreate:

- `.env`
- `compose.yaml`
- any stale `config.d/*`

Run the install steps again from the top.

This wipes the current installation data. Do not do it on a host whose data
you intend to preserve.

## Current TODOs

- publish official images so deployment no longer depends on `rsync`
- provide a first-class reverse-proxy example
- document backup and restore flows
- document production upgrades as a first-class operator workflow
- document the external agent deployment path after CoreMatrix itself is stable
