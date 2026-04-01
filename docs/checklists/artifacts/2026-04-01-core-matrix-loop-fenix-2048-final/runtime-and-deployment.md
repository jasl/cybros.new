# Runtime And Deployment

## Reset

- Reset disposable workspace:
  - `/Users/jasl/Workspaces/Ruby/cybros/tmp/fenix`
- Removed prior Docker containers:
  - `fenix-capstone`
  - `fenix-capstone-proxy`
- Removed prior Docker volumes:
  - `fenix_capstone_storage`
  - `fenix_capstone_proxy_routes`
- Reset `Core Matrix` development database:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails db:drop db:create db:migrate
```

## Core Matrix

Started host-side runtime services:

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

Recreated Dockerized `Fenix` runtime and proxy:

```bash
docker run -d --name fenix-capstone -p 3101:80 \
  -e RAILS_ENV=production \
  -e SECRET_KEY_BASE=fenix-capstone-dev-only-secret-key-base \
  -e FENIX_PUBLIC_BASE_URL=http://127.0.0.1:3101 \
  -e PLAYWRIGHT_BROWSERS_PATH=/rails/.playwright \
  -e FENIX_DEV_PROXY_PORT=3310 \
  -e FENIX_DEV_PROXY_ROUTES_FILE=/rails/tmp/dev-proxy/routes.caddy \
  -v /Users/jasl/Workspaces/Ruby/cybros/tmp/fenix:/workspace \
  -v fenix_capstone_storage:/rails/storage \
  -v fenix_capstone_proxy_routes:/rails/tmp/dev-proxy \
  fenix-capstone-image

docker run -d --name fenix-capstone-proxy -p 3310:3310 \
  -e PLAYWRIGHT_BROWSERS_PATH=/rails/.playwright \
  -e FENIX_DEV_PROXY_PORT=3310 \
  -e FENIX_DEV_PROXY_ROUTES_FILE=/rails/tmp/dev-proxy/routes.caddy \
  -v /Users/jasl/Workspaces/Ruby/cybros/tmp/fenix:/workspace \
  -v fenix_capstone_proxy_routes:/rails/tmp/dev-proxy \
  fenix-capstone-image /rails/bin/fenix-dev-proxy
```

Synced local `agents/fenix` code into the running container and prepared the DB:

```bash
tar --exclude='.git' --exclude='node_modules' --exclude='tmp' --exclude='storage' \
  -C /Users/jasl/Workspaces/Ruby/cybros/agents/fenix -cf - . | \
  docker exec -i fenix-capstone tar -xf - -C /rails

docker exec fenix-capstone sh -lc 'chown -R 1000:1000 /rails && cd /rails && bin/rails db:prepare'
```

Manifest probe:

```bash
curl -fsS http://127.0.0.1:3101/runtime/manifest
```

## Registration And Worker Start

Registered the bundled runtime from the published manifest and issued a new machine credential. Public artifacts:

- Deployment `public_id`: `019d49d0-3ce2-773e-a3fe-fd438ba097bc`
- Execution environment `public_id`: `019d49d0-3ccf-7280-b65d-c2233c9f178f`
- Redacted registration artifact: `acceptance-registration.json`

Started the persistent runtime worker after registration with the same base URL and machine credential:

```bash
docker exec \
  -e CORE_MATRIX_BASE_URL=http://host.docker.internal:3000 \
  -e CORE_MATRIX_MACHINE_CREDENTIAL=bundled-runtime:capstone-fenix-v1 \
  -it fenix-capstone sh -lc 'cd /rails && bin/runtime-worker'
```

The runtime worker handled both the control loop and local Solid Queue execution during the acceptance run.
