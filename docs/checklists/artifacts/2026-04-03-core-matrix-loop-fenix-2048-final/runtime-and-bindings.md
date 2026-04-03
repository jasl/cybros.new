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

Fresh-start automation rebuilt and recreated the Dockerized `Fenix`
runtime container from the current local `agents/fenix` checkout.

- Container: `fenix-capstone`
- Public runtime base URL: `http://127.0.0.1:3101`

The top-level automation reset the Dockerized runtime by removing the
`fenix_capstone_storage` volume before boot so no in-run database reset was
needed.

```bash
docker volume rm -f fenix_capstone_storage
bash script/manual/acceptance/fresh_start_stack.sh
```

Manifest probe:

```bash
curl -fsS http://127.0.0.1:3101/runtime/manifest
```

## Registration And Worker Start

Registered the bundled runtime from the published manifest and issued a new machine credential. Public bindings:

- Agent program `public_id`: `019d5565-9c96-7633-a356-7598a080bd0e`
- Agent program version `public_id`: `019d5565-9ca0-7a8c-bb58-137cf4b918f8`
- Execution runtime `public_id`: `019d5565-9c83-7c06-89e5-2a1fd4ab3fe1`
- Skill source manifest: `/Users/jasl/Workspaces/Ruby/cybros/tmp/fenix/skill-sources/skill-source-manifest.json`

After runtime registration, the top-level automation recreated the
Dockerized `Fenix` container with the issued machine credentials in its
environment, then started the persistent runtime worker:

```bash
FENIX_MACHINE_CREDENTIAL=9fe73f6eb28e57a2c3278e9b13bce7a05f374a3c8e11a9762b8d4e51080089d9 FENIX_EXECUTION_MACHINE_CREDENTIAL=9fe73f6eb28e57a2c3278e9b13bce7a05f374a3c8e11a9762b8d4e51080089d9 DOCKER_CORE_MATRIX_BASE_URL=http://host.docker.internal:3000 bash script/manual/acceptance/activate_fenix_docker_runtime.sh
```

The runtime worker booted through `bin/runtime-worker`, which reused Puma's embedded Solid Queue supervisor and only started the persistent control loop.

Worker entrypoint(s):

- `bin/runtime-worker`
