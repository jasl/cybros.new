# Runtime And Deployment

## Stack Shape

- `Core Matrix` ran from the local Rails checkout in `/Users/jasl/Workspaces/Ruby/cybros/core_matrix`.
- `Fenix` ran as the paired external runtime in Docker.
- The Fenix runtime base URL for this acceptance flow was `http://127.0.0.1:3101`.
- The mounted disposable runtime workspace on the host was `/Users/jasl/Workspaces/Ruby/cybros/tmp/fenix`.
- Inside the Fenix container that workspace was available at `/workspace`.

## Runtime Processes

- `Core Matrix` web: `cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && bin/rails server -b 127.0.0.1 -p 3000`
- `Core Matrix` jobs: `cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && bin/jobs start`
- `Fenix` runtime worker: `docker exec -e CORE_MATRIX_BASE_URL=http://host.docker.internal:3000 -e CORE_MATRIX_MACHINE_CREDENTIAL=<redacted> -it fenix-capstone sh -lc 'cd /rails && bin/runtime-worker'`
- Singleton runtime-worker check: one `bin/runtime-worker` shell plus one `runtime:control_loop_forever` process were observed before the accepted run.

## Reset And Registration

- `Core Matrix` databases were dropped and recreated before the run.
- The Dockerized `Fenix` runtime database, queue database, workspace project, and `.fenix/.codex/.agents` directories were cleared before the run.
- Registration artifact: `tmp/acceptance-registration.json`
- Deployment public_id: `019d4916-cd5a-7d47-b030-04e3e6471a9c`
- Execution environment public_id: `019d4916-cd34-76ca-a845-dc01a90e597f`

## Acceptance Run Identity

- Conversation public_id: `019d4918-4baf-7fcf-9c6c-483f238595d2`
- Turn public_id: `019d4918-4c40-7162-9a5b-b79c62b1c34b`
- Workflow run public_id: `019d4918-4ca1-747e-9ba7-46caa8623b8b`
- Provider handle: `openrouter`
- Model ref: `openai-gpt-5.4-live-acceptance`
- API model: `openai/gpt-5.4`

## Primary Proof Artifact

- Full exported run data: `run-summary.json`
