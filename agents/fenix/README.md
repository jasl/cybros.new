# Fenix

`fenix` is the default out-of-the-box agent program for Core Matrix.

Fenix has two jobs:

- ship as a usable general assistant product
- serve as the first technical validation program for the Core Matrix loop

## Product Definition

Fenix is a practical assistant that combines:

- general-assistant conversation behavior inspired by `openclaw`
- coding-assistant behavior inspired by Codex-style workflows
- everyday office-assistance behavior inspired by `accomplish` and `maxclaw`

Fenix may define agent-specific tools, deterministic program logic, and
composer completions such as slash commands or symbol-triggered references. It
does not need every interaction to be driven by an LLM.

## Boundary

Fenix is not:

- the kernel itself
- the home for every future product shape
- a universal agent meant to absorb all future experiments

When Core Matrix needs to validate materially different product shapes, those
should land in separate agent programs rather than forcing them into Fenix.

## Role Today

- prove the real agent loop end to end
- become the first full Web product on top of the validated kernel
- remain one validated product while other agent programs prove the
  kernel is reusable beyond Fenix

## Runtime Surface

`Fenix` now exposes one stable machine-facing pairing endpoint:

- `GET /runtime/manifest`

`GET /runtime/manifest` publishes the registration metadata needed for external
pairing:

- protocol version
- SDK version
- protocol methods
- tool catalog
- `profile_catalog`
- `program_plane`
- `execution_plane`
- `effective_tool_catalog`
- config schema snapshots
- default config snapshot

The manifest now also carries a small runtime-foundation block inside
`execution_capability_payload.runtime_foundation` so operators can inspect the
expected host/toolchain baseline without reading deployment docs first. The
current baseline is:

- canonical container base: Ubuntu 24.04
- Ruby pinned by [.ruby-version](/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/.ruby-version)
- Node pinned by [.node-version](/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/.node-version)
- Python pinned by [.python-version](/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/.python-version)
- shared bootstrap scripts:
  - [bootstrap-runtime-deps.sh](/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/scripts/bootstrap-runtime-deps.sh)
  - [bootstrap-runtime-deps-darwin.sh](/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/scripts/bootstrap-runtime-deps-darwin.sh)

The manifest now declares runtime-owned profile and subagent defaults:

- `default_config_snapshot.interactive.profile` is fixed to `main` for root
  interactive conversations in this batch
- `default_config_snapshot.subagents.enabled`
- `default_config_snapshot.subagents.allow_nested`
- `default_config_snapshot.subagents.max_depth`
- `conversation_override_schema_snapshot` exposes only `subagents.*`

The current pairing contract models `Fenix` as one process serving both:

- `AgentRuntime`
- `ExecutionRuntime`

That dual role is explicit in the manifest even though the current runtime still ships it
as one bundled runtime.

Normal execution and close control do not use a runtime callback endpoint.
`Core Matrix` is the orchestration truth and delivers mailbox items through the
control plane:

- realtime push over `/cable`
- `POST /program_api/control/poll` fallback delivery
- `POST /program_api/control/report` for incremental reports back into the kernel

The manifest therefore exists for registration and capability advertisement,
not for direct execution dispatch. The runtime still keeps deterministic local
execution logic, but product execution now rides the mailbox-first control
plane shared by bundled and external pairing.

Long-lived environment resources also require a persistent mailbox worker.
`Fenix` ships:

- `bin/rails runtime:control_loop_once`
  - one-shot realtime-or-poll worker used for targeted checks and short-lived
    mailbox execution
- `bin/rails runtime:control_loop_forever`
  - persistent websocket-first worker that retains local `ProcessRun` handles
    across mailbox iterations so later close requests can settle gracefully
- `bin/jobs start`
  - starts the local Solid Queue workers that execute `RuntimeExecutionJob`
    across the runtime topology queues
- `bin/runtime-worker`
  - convenience wrapper that starts `bin/jobs start` in the background and then
    runs `bin/rails runtime:control_loop_forever`

When `Fenix` is registered as an external runtime, the control loop and the job
worker must run with the same `CORE_MATRIX_BASE_URL` and
`CORE_MATRIX_MACHINE_CREDENTIAL`. The queue worker is not optional in the
default `solid_queue` topology because `MailboxWorker` enqueues runtime
execution onto `runtime_prepare_round`, `runtime_pure_tools`,
`runtime_process_tools`, and `runtime_control`.

Detached long-lived services therefore follow this contract:

- `process_exec` first asks Core Matrix to create one `ProcessRun`
- `Fenix` launches the local process only after that durable resource exists
- the persistent control worker reports `process_started`, `process_output`,
  `process_exited`, and `resource_close_*` over the control plane

Long-lived services are now plugin-backed rather than hardcoded in the pairing
manifest. `process_exec` routes through a dedicated process runtime family:

- [plugin.yml](/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/app/services/fenix/plugins/system/process/plugin.yml)
- [runtime.rb](/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/app/services/fenix/plugins/system/process/runtime.rb)
- [launcher.rb](/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/app/services/fenix/processes/launcher.rb)

When a tool call passes `proxy_port`, `Fenix` also registers a stable fixed-port
proxy path under `/dev/<process_run_id>/*`. The proxy registry renders Caddy
routes into `tmp/dev-proxy/routes.caddy`, and
[bin/fenix-dev-proxy](/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/bin/fenix-dev-proxy)
boots Caddy with [config/caddy/Caddyfile](/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/config/caddy/Caddyfile)
to expose those paths on the external proxy port.

## Web Tool Surface

`Fenix` now exposes a first local web capability slice through the execution
tool catalog:

- `web_fetch`
  - local `http/https` fetch with SSRF/private-address blocking
  - redirect targets are revalidated before following
  - HTML is reduced to readable text for the agent-facing payload
- `web_search`
  - generic provider-backed search entrypoint
  - current default provider is Firecrawl
- `firecrawl_search`
  - explicit Firecrawl search surface
- `firecrawl_scrape`
  - explicit Firecrawl scrape surface

Firecrawl-backed tools use:

- `FIRECRAWL_API_KEY`
  - required for `web_search`, `firecrawl_search`, and `firecrawl_scrape`
- `FIRECRAWL_BASE_URL`
  - optional override
  - defaults to `https://api.firecrawl.dev`

## Browser Tool Surface

`Fenix` now exposes a dedicated browser session surface:

- `browser_list`
- `browser_open`
- `browser_navigate`
- `browser_session_info`
- `browser_get_content`
- `browser_screenshot`
- `browser_close`

Browser sessions remain runtime-local handles rather than kernel-owned
resources. The first cut uses Playwright-managed Chromium through
[session_host.mjs](/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/scripts/browser/session_host.mjs).

The Docker build installs the Playwright browser bundle during image creation.
Operators can still override the browser executable path with:

- `PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH`

## Operator Surface

The current runtime surface is organized around five operator object families:

- `workspace`
- `memory`
- `command_run`
- `process_run`
- `browser_session`

That object model is reflected in the pairing manifest, local `.fenix`
operator snapshot, and the built-in operator prompt layer.

Attached command runs currently expose:

- `exec_command`
- `write_stdin`
- `command_run_list`
- `command_run_read_output`
- `command_run_wait`
- `command_run_terminate`

Detached process runs currently expose:

- `process_exec`
- `process_list`
- `process_read_output`
- `process_proxy_info`

Browser sessions currently expose:

- `browser_list`
- `browser_open`
- `browser_session_info`
- `browser_navigate`
- `browser_get_content`
- `browser_screenshot`
- `browser_close`

For a full local smoke path, run:

```bash
bin/rails runner script/manual/operator_surface_smoke.rb
```

## Retained Hook Lifecycle

`Fenix` keeps a stage-shaped runtime surface instead of collapsing behavior
into one opaque callback.

Current retained hooks:

- `prepare_turn`
- `compact_context`
- `review_tool_call`
- `project_tool_result`
- `finalize_output`
- `handle_error`

The runtime executor calls them in order for successful execution and records a
trace entry for each stage. Failure paths append `handle_error` and emit
`execution_fail`.

## Estimation Helpers

`Fenix` also retains local advisory helpers:

- `estimate_tokens`
- `estimate_messages`

These are deliberately local runtime helpers rather than kernel primitives.
They support preflight budgeting and compaction decisions before any future
provider call.

## Likely-Model Hints

Assignments primarily carry model hints through:

- `payload.model_context.model_ref`
- `payload.model_context.api_model`

`Fenix` also accepts older compatibility fallbacks such as
`payload.model_context.likely_model` or `payload.provider_execution.model_ref`.
When the estimated token load exceeds
`payload.budget_hints.advisory_hints.recommended_compaction_threshold`,
`compact_context`
uses the resolved model hint to explain why compaction happened and records the
before or after message counts in the hook trace.

## Current Validation Path

The current runtime validation path is intentionally small and deterministic:

- `deterministic_tool` reviews a local calculator tool call, projects the tool
  result, and finalizes a user-facing output
- `raise_error` proves the error hook and terminal failure reporting

This preserves the runtime-stage contract needed for later mixed
code-plus-LLM execution without forcing prompt building or provider transport
back into the kernel.

Prompt building, prompt-template choice, and profile-specific tool semantics
remain inside `Fenix`. Core Matrix computes and freezes the
conversation-visible tool set into `agent_context.allowed_tool_names`, and
`Fenix::Hooks::ReviewToolCall` treats that frozen set as a real execution-time
constraint rather than trace-only metadata.

## Skill Surface

`Fenix` now keeps the skill boundary inside the agent program rather
than pushing skills into `Core Matrix`.

Skill roots are separated intentionally:

- `skills/.system/<name>/` for reserved built-in `Fenix` skills
- `skills/.curated/<name>/` for bundled curated catalog entries
- `skills/<name>/` for live installed third-party skills

The current minimal skill surface is:

- `skills_catalog_list`
- `skills_load`
- `skills_read_file`
- `skills_install`

That surface is sufficient to:

- discover reserved system skills and bundled curated entries
- load one active system or installed skill body on demand
- read additional files relative to an active skill root
- stage and promote a third-party skill into the live root

By default, the live skill root now lives under `tmp/skills-live` so runtime
install state does not pollute the tracked repo tree.

The current runtime keeps two explicit rules:

- `.system` skill names are reserved and may not be overridden
- installs become effective on the next top-level turn, not mid-turn

The built-in `deploy-agent` system skill exists to prove that `Fenix` can use
its own skill mechanism for an operational workflow, not just passive
instruction storage.

## Manual Acceptance Runtime Layout

The retained manual-acceptance layout uses two local `Fenix` processes:

- `AGENT_FENIX_PORT=3101 bin/dev`
  - default bundled/external runtime validation
  - bundled mailbox execution
  - external pairing
  - deployment rotation
  - pairs with `bin/runtime-worker` for external mailbox execution and
    long-lived `ProcessRun` validation
- `AGENT_FENIX_PORT=3102 ... bin/dev`
  - dedicated skills-validation runtime
  - `FENIX_LIVE_SKILLS_ROOT=/tmp/fenix-live-skills`
  - `FENIX_STAGING_SKILLS_ROOT=/tmp/fenix-staging`
  - `FENIX_BACKUP_SKILLS_ROOT=/tmp/fenix-backups`

The dedicated `3102` runtime keeps live, staging, and backup skill writes out
of the repo tree so the checked-in skill catalog stays reproducible. The manual
acceptance scripts intentionally clear those `/tmp/fenix-*` roots before
scenarios `12` and `13`.

## Deployment Rotation

`Fenix` treats release change as deployment rotation:

- boot a new `Fenix` release as a new deployment
- expose the same manifest and mailbox control contract
- register it with Core Matrix
- cut future work over once the new deployment reaches healthy runtime
  participation

There is no in-place self-updater in the current runtime. Upgrade and downgrade are the
same kernel-facing operation.

## Distribution Contract

`Fenix` now documents one concrete distribution shape that matches the pairing
manifest:

- Docker Compose is the default deployment path
- Ubuntu 24.04 is the canonical bare-metal host
- macOS remains a best-effort development environment

### Docker Compose

Use [docker-compose.fenix.yml](/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/docker-compose.fenix.yml)
as the default sample:

- `fenix`
  - main Rails runtime
  - mounts `./tmp/docker-workspace:/workspace`
  - persists SQLite state in `/rails/storage`
  - exposes `3101 -> 80`
- `fenix-dev-proxy`
  - runs [bin/fenix-dev-proxy](/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/bin/fenix-dev-proxy)
  - serves the fixed-port developer proxy on `3310`
  - shares `tmp/dev-proxy/routes.caddy` through the `fenix_proxy_routes` volume

Key environment variables in the sample:

- `SECRET_KEY_BASE=...`
  - `Fenix` resolves runtime secrets through `Rails.app.creds`, so Docker
    deployments should provide them through ENV instead of mounting
    `config/master.key`
  - the sample uses a dev-only placeholder so `production` boots out of the box
  - replace it with a real secret for any non-local deployment
- `FENIX_PUBLIC_BASE_URL=http://localhost:3101`
  - the sample publishes the reachable manifest base URL explicitly
  - set this to the externally reachable origin when a reverse proxy or TLS
    terminator changes the public scheme/host/port
- `CORE_MATRIX_BASE_URL`
- `CORE_MATRIX_MACHINE_CREDENTIAL`
- `PLAYWRIGHT_BROWSERS_PATH=/rails/.playwright`
- `FENIX_DEV_PROXY_PORT=3310`
- `FENIX_DEV_PROXY_ROUTES_FILE=/rails/tmp/dev-proxy/routes.caddy`

Named volumes in the sample:

- `fenix_storage`
  - persists `production.sqlite3` under `/rails/storage`
- `fenix_proxy_routes`
  - shares the generated Caddy route fragments between `fenix` and
    `fenix-dev-proxy`

### Ubuntu 24.04 Bare Metal

The canonical bare-metal target is Ubuntu 24.04. Operators should:

- install runtime dependencies with
  [bootstrap-runtime-deps.sh](/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/scripts/bootstrap-runtime-deps.sh)
- run `npm ci`
- run `npx playwright install chromium`
- provide `CORE_MATRIX_BASE_URL` and `CORE_MATRIX_MACHINE_CREDENTIAL`
- provide runtime secrets through ENV-backed `Rails.app.creds`
- start the Rails runtime and, when proxy paths are needed, start
  `bin/fenix-dev-proxy`

### macOS Development Caveats

macOS is supported for development and validation, but not treated as the
canonical appliance baseline:

- use
  [bootstrap-runtime-deps-darwin.sh](/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/scripts/bootstrap-runtime-deps-darwin.sh)
- run `npm ci`
- run `npx playwright install chromium`
- keep using `PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH` only if you intentionally
  want a non-default browser binary
