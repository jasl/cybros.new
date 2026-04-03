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

Synced local `agents/fenix` code into the running container and performed a destructive in-container database reset:

```bash
docker exec fenix-capstone sh -lc 'cd /rails && export RAILS_ENV=development DISABLE_DATABASE_ENVIRONMENT_CHECK=1 && (bin/rails db:drop || true) && bin/rails db:create && bin/rails db:migrate && bin/rails db:seed'
```

Manifest probe:

```bash
curl -fsS http://127.0.0.1:3101/runtime/manifest
```

## Registration And Worker Start

Registered the bundled runtime from the published manifest and issued a new machine credential. Public bindings:

- Agent program `public_id`: `019d52da-cdf9-72fa-9ca3-94b87091d175`
- Agent program version `public_id`: `019d52da-ce01-7da4-9b6c-c48e27e8ed76`
- Execution runtime `public_id`: `019d52da-cdec-7834-850f-6eb59ea31d2d`
- Skill source manifest: `/Users/jasl/Workspaces/Ruby/cybros/tmp/fenix/skill-sources/skill-source-manifest.json`

Restarted the persistent runtime worker after registration with the same base URL and machine credential:

```bash
docker exec   -e CORE_MATRIX_BASE_URL=http://host.docker.internal:3000   -e CORE_MATRIX_MACHINE_CREDENTIAL=15109de50cf8bb047347d53d9ff7a6a830112f5a1d985d0e63d993fd48b621c7   -d fenix-capstone sh -lc 'cd /rails && exec bin/jobs start >>/tmp/runtime-jobs.log 2>&1'

docker exec   -e CORE_MATRIX_BASE_URL=http://host.docker.internal:3000   -e CORE_MATRIX_MACHINE_CREDENTIAL=15109de50cf8bb047347d53d9ff7a6a830112f5a1d985d0e63d993fd48b621c7   -d fenix-capstone sh -lc 'cd /rails && exec bin/rails runtime:control_loop_forever >>/tmp/runtime-control.log 2>&1'
```

The runtime worker handled both the control loop and local Solid Queue execution during the acceptance run.
