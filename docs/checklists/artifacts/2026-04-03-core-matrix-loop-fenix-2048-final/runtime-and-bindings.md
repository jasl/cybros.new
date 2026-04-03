# Runtime And Bindings

## Reset

- Reset disposable workspace:
  - `/Users/jasl/Workspaces/Ruby/cybros/tmp/fenix`
- Reset `Core Matrix` development database with:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails db:drop
rm db/schema.rb
bin/rails db:create
bin/rails db:migrate
bin/rails db:reset
```

## Core Matrix

Started host-side services with:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails server -b 127.0.0.1 -p 3000
bin/jobs start
```

Health check:

```bash
curl -fsS http://127.0.0.1:3000/up
```

## Dockerized Fenix

Reused the existing Dockerized `Fenix` runtime container:

- Container: `fenix-capstone`
- Public runtime base URL: `http://127.0.0.1:3101`

Synced local `agents/fenix` code into the running container and refreshed the in-container database:

```bash
docker exec fenix-capstone sh -lc 'cd /rails && bin/rails db:prepare'
```

Manifest probe:

```bash
curl -fsS http://127.0.0.1:3101/runtime/manifest
```

## Registration And Worker Start

Registered the bundled runtime from the published manifest and issued a new machine credential. Public bindings:

- Agent program `public_id`: `019d5091-027a-7d0b-a38f-241e3254f8a1`
- Agent program version `public_id`: `019d5091-0284-7915-b4bb-7ba5cfe83a6e`
- Execution runtime `public_id`: `019d5091-026c-7800-bfc8-e0bf4b410e88`
- Skill source manifest: `/Users/jasl/Workspaces/Ruby/cybros/tmp/fenix/skill-sources/skill-source-manifest.json`

Restarted the persistent runtime worker after registration with the same base URL and machine credential:

```bash
docker exec   -e CORE_MATRIX_BASE_URL=http://host.docker.internal:3000   -e CORE_MATRIX_MACHINE_CREDENTIAL=d1842ecd83d9dd79476df058e0d9f477d75deb21a060232edf0406482a470a5e   -d fenix-capstone sh -lc 'cd /rails && exec bin/jobs start >>/tmp/runtime-jobs.log 2>&1'

docker exec   -e CORE_MATRIX_BASE_URL=http://host.docker.internal:3000   -e CORE_MATRIX_MACHINE_CREDENTIAL=d1842ecd83d9dd79476df058e0d9f477d75deb21a060232edf0406482a470a5e   -d fenix-capstone sh -lc 'cd /rails && exec bin/rails runtime:control_loop_forever >>/tmp/runtime-control.log 2>&1'
```

The runtime worker handled both the control loop and local Solid Queue execution during the acceptance run.
