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
docker exec fenix-capstone sh -lc 'cd /rails && export RAILS_ENV=production DISABLE_DATABASE_ENVIRONMENT_CHECK=1 && (bin/rails db:drop || true) && bin/rails db:create && bin/rails db:migrate && bin/rails db:seed'
```

Manifest probe:

```bash
curl -fsS http://127.0.0.1:3101/runtime/manifest
```

## Registration And Worker Start

Registered the bundled runtime from the published manifest and issued a new machine credential. Public bindings:

- Agent program `public_id`: `019d5432-02e9-7fc4-9ed5-593e22297f26`
- Agent program version `public_id`: `019d5432-02f3-74c8-9dd8-ceec99a15712`
- Execution runtime `public_id`: `019d5432-02df-7696-83c8-40f75f1ce774`
- Skill source manifest: `/Users/jasl/Workspaces/Ruby/cybros/tmp/fenix/skill-sources/skill-source-manifest.json`

Restarted the persistent runtime worker after registration with the same base URL and machine credential:

```bash
docker exec   -e CORE_MATRIX_BASE_URL=http://host.docker.internal:3000   -e CORE_MATRIX_MACHINE_CREDENTIAL=d71c14e4817305d590e7c0c6654c09f5d7c5dab968b4b917b16a1b750286674a   -e RAILS_ENV=production   -e FENIX_WORKSPACE_ROOT=/workspace   -d fenix-capstone sh -lc 'cd /rails && exec bin/jobs start >>/tmp/runtime-jobs.log 2>&1'

docker exec   -e CORE_MATRIX_BASE_URL=http://host.docker.internal:3000   -e CORE_MATRIX_MACHINE_CREDENTIAL=d71c14e4817305d590e7c0c6654c09f5d7c5dab968b4b917b16a1b750286674a   -e RAILS_ENV=production   -e FENIX_WORKSPACE_ROOT=/workspace   -d fenix-capstone sh -lc 'cd /rails && exec bin/rails runtime:control_loop_forever >>/tmp/runtime-control.log 2>&1'
```

The runtime worker handled both the control loop and local Solid Queue execution during the acceptance run.
