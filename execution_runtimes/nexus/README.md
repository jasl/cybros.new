# Nexus

`nexus` is the default out-of-the-box execution runtime for Core Matrix.

Nexus has two jobs:

- ship as the default execution appliance for bundled and external runs
- serve as the first technical validation runtime for the Core Matrix loop

## Monorepo Role

`execution_runtimes/nexus` is the active execution-runtime app in this monorepo.

- active runtime work lands in `execution_runtimes/nexus`
- the default Docker runtime base lives in `images/nexus`

## Verification

Run the documented project checks from the app directory:

```bash
cd execution_runtimes/nexus
bin/brakeman --no-pager
bin/bundler-audit
bin/rubocop -f github
bin/rails db:test:prepare
bin/rails test
```

## Product Definition

Nexus is the execution appliance that combines:

- execution-runtime tool routing
- filesystem-backed skill package access
- filesystem-backed memory storage
- process, browser, and external tool execution

## Boundary

Nexus is not:

- the kernel itself
- the home for every future product shape
- a universal agent meant to absorb all future experiments

When Core Matrix needs to validate materially different runtime shapes, those
should land in separate runtimes rather than forcing them into Nexus.

## Role Today

- prove the real agent/runtime loop end to end
- become the default bundled execution runtime
- remain one validated runtime while other runtimes prove the
  kernel is reusable beyond Nexus

## Runtime Surface

`Nexus` now exposes one stable runtime-facing pairing endpoint:

- `GET /runtime/manifest`

`GET /runtime/manifest` publishes the registration metadata needed for external
pairing:

- protocol version
- SDK version
- protocol methods
- tool catalog
- `profile_catalog`
- `agent_plane`
- `execution_runtime_plane`
- `effective_tool_catalog`
- config schema snapshots
- default config snapshot

The manifest now also carries a small runtime-foundation block inside
`execution_runtime_capability_payload.runtime_foundation` so operators can inspect the
expected host/toolchain baseline without reading deployment docs first. The
current baseline is:

- canonical Docker base: [images/nexus](/Users/jasl/Workspaces/Ruby/cybros/images/nexus) on Ubuntu 24.04
- installable tool versions pinned in [versions.env](/Users/jasl/Workspaces/Ruby/cybros/images/nexus/versions.env)
- Ruby pinned by [.ruby-version](/Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/.ruby-version)
- bare-metal host validator: [bin/check-runtime-host](/Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/bin/check-runtime-host)

The manifest now declares runtime-owned profile and subagent defaults:

- `default_config_snapshot.interactive.profile` is fixed to `main` for root
  interactive sessions in this batch
- `default_config_snapshot.model_slots.summary`
  - points supervision sidechat summarization at `role:summary`
- `default_config_snapshot.subagents.enabled`
- `default_config_snapshot.subagents.allow_nested`
- `default_config_snapshot.subagents.max_depth`
- `conversation_override_schema_snapshot` exposes only `subagents.*`

The current pairing contract models `Nexus` as an execution-runtime-only
participant.

Normal execution and close control do not use a runtime callback endpoint.
`Core Matrix` is the orchestration truth and delivers mailbox items through the
control plane:

- realtime push over `/cable`
- `POST /execution_runtime_api/control/poll` fallback delivery
- `POST /execution_runtime_api/control/report` for incremental reports back into the kernel

The manifest therefore exists for registration and capability advertisement,
not for direct execution dispatch. Product execution now rides the
execution-runtime mailbox-first control plane shared by bundled and external
pairing.

Long-lived runtime resources also require a persistent mailbox worker.
`Nexus` ships:

- `bin/rails runtime:control_loop_once`
  - one-shot realtime-or-poll worker used for targeted checks and short-lived
    mailbox execution
- `bin/rails runtime:control_loop_forever`
  - persistent websocket-first worker that retains local `ProcessRun` handles
    across mailbox iterations so later close requests can settle gracefully
- `bin/jobs start`
  - starts the local Solid Queue workers that execute `MailboxExecutionJob`
    across the runtime topology queues
  - only needed in the standalone worker topology, where the web process runs
    with `STANDALONE_SOLID_QUEUE=true`
- `bin/runtime-worker`
  - convenience wrapper for the external runtime worker process
  - always runs `bin/rails runtime:control_loop_forever`
  - when `STANDALONE_SOLID_QUEUE=true`, it also starts `bin/jobs start` in the
    background before entering the control loop

When `Nexus` is registered as an external runtime, the control loop and the job
worker must run with the same `CORE_MATRIX_BASE_URL` and
`CORE_MATRIX_AGENT_CONNECTION_CREDENTIAL`.

In the default single-service deployment, Puma embeds the Solid Queue
supervisor, so only the control loop must be started separately. When you
split web and worker responsibilities across processes, enable
`STANDALONE_SOLID_QUEUE=true` for the web process and run either `bin/jobs
start` plus `bin/rails runtime:control_loop_forever`, or use
`bin/runtime-worker`.

Detached long-lived services therefore follow this contract:

- `process_exec` first asks Core Matrix to create one `ProcessRun`
- `Nexus` launches the local process only after that durable resource exists
- the persistent control worker reports `process_started`, `process_output`,
  `process_exited`, and `resource_close_*` over the control plane

Detached process tools are implemented directly in the runtime service layer:

- [process.rb](/Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/app/services/tool_executors/process.rb)
- [launcher.rb](/Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/app/services/processes/launcher.rb)
- [manager.rb](/Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/app/services/processes/manager.rb)
- [proxy_registry.rb](/Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/app/services/processes/proxy_registry.rb)

When a tool call passes `proxy_port`, `Nexus` also registers a stable fixed-port
proxy path under `/dev/<process_run_id>/*`. The proxy registry renders Caddy
routes into `tmp/dev-proxy/routes.caddy`, and
[bin/nexus-dev-proxy](/Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/bin/nexus-dev-proxy)
boots Caddy with [config/caddy/Caddyfile](/Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/config/caddy/Caddyfile)
to expose those paths on the external proxy port.

## Web Tool Surface

`Nexus` now exposes a first local web capability slice through the execution
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

`Nexus` now exposes a dedicated browser session surface:

- `browser_list`
- `browser_open`
- `browser_navigate`
- `browser_session_info`
- `browser_get_content`
- `browser_screenshot`
- `browser_close`

Browser sessions remain runtime-local handles rather than kernel-owned
resources. The first cut uses Playwright-managed Chromium through
[session_host.mjs](/Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/scripts/browser/session_host.mjs).

Internally, `Nexus` now keeps its product-level services directly under
`*`:

- `Prompts`, `Memory`, `Skills`, and `Requests`
  - prompt assembly, filesystem-backed memory, skill package access, and
    agent-facing request handling
- `Browser`, `Processes`, `ToolExecutors`,
  `CommandRunRegistry`, and `SystemToolRegistry`
  - command runs, detached processes, browser sessions, and runtime tool
    registry
- `Shared`
  - control-plane transport, environment overlays, and shared value objects

`Runtime` remains only as the appliance/entry layer that routes mailbox
work, runs the control loop, and assembles the external manifest.

Docker deployments inherit Playwright plus Chromium from
[images/nexus](/Users/jasl/Workspaces/Ruby/cybros/images/nexus). Bare-metal
operators can override the browser executable path with:

- `PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH`

Bare-metal hosts also need a globally installed Playwright package that matches
the Nexus matrix. `Nexus` then uses `uv` to provision a managed Python runtime
under `NEXUS_HOME_ROOT/python`, defaulting to `~/.nexus/python` when
`NEXUS_HOME_ROOT` is unset. Once the agent boots, `python`, `python3`, `pip`,
and `pip3` resolve from that managed runtime inside the agent process. A
typical host bootstrap looks like:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
npm install -g "playwright@$(awk -F= '/^PLAYWRIGHT_VERSION=/{print $2}' images/nexus/versions.env)"
playwright install chromium
bin/check-runtime-host
```

## Runtime Command Matrix

Inside the running `Nexus` agent process, the out-of-the-box command surface is:

- system-level commands available without bootstrap:
  - `ruby`, `bundle`
  - `node`, `npm`, `pnpm`, `corepack`
  - `playwright`, `vite`, `create-vite`
  - `uv`
  - `go`
  - `rustc`, `cargo`
  - `git`, `curl`, `jq`, `rg`, `fd`, `sqlite3`
  - Chromium/Chrome browser executables
- managed runtime commands available after `Nexus` bootstraps the host:
  - `python`, `python3`
  - `pip`, `pip3`

That split is intentional:

- `images/nexus` provides the stable system toolchain directly
- `Nexus` owns the managed Python runtime under `NEXUS_HOME_ROOT/python`
- agent-executed commands see both layers through the process `PATH`

## Workspace Env Overlay

`Nexus` now supports one workspace-scoped execution overlay file:

- `.nexus/workspace.env`

The overlay is intentionally narrow:

- it applies only to `exec_command`
- it applies only to `process_exec`
- it merges over the runtime baseline `ENV` for that child process only
- it does not mutate the Rails/Nexus process `ENV`
- it does not apply to Rails boot, mailbox workers, browser sessions, or skill
  repository scope

Parsing rules are strict:

- blank lines are ignored
- `#` comments are ignored
- `export KEY=value` is accepted
- only `KEY=VALUE` assignments are accepted
- keys must match `\A[A-Z][A-Z0-9_]*\z`
- no shell evaluation, interpolation, or multiline values

Reserved runtime-owned keys are rejected instead of silently ignored. The first
cut blocks overlays for:

- `CORE_MATRIX_*`
- `ACTIVE_RECORD_ENCRYPTION__*`
- `SECRET_KEY_BASE`
- `RAILS_ENV`
- `DATABASE_URL`
- `BUNDLE_GEMFILE`
- `BUNDLE_PATH`
- `NEXUS_HOME_ROOT`
- `NEXUS_PYTHON_ROOT`
- `NEXUS_PYTHON_INSTALL_ROOT`
- `UV_PYTHON_INSTALL_DIR`
- `PLAYWRIGHT_BROWSERS_PATH`
- `PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH`
- `PATH`

Example:

```dotenv
HELLO=workspace
FEATURE_FLAG=enabled
```

From that workspace, `exec_command` and `process_exec` child processes see
those values. If the file is invalid, the execution request fails with the
normal tool validation error envelope.

## Operator Surface

The current runtime surface is organized around five operator object families:

- `workspace`
- `memory`
- `command_run`
- `process_run`
- `browser_session`

That object model is reflected in the pairing manifest, local `.nexus`
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

## Agent Tool Slice

The built-in agent tools are currently:

- `compact_context`
- `calculator`

`compact_context` remains an agent-owned helper. It estimates token load from
the provided messages, applies the advisory compaction threshold from
`budget_hints`, and emits a compacted message list when necessary. The only
current model hint consumed by this helper is:

- `payload.provider_context.model_context.model_slug`

There is no separate `estimate_tokens` or `estimate_messages` runtime surface.
Those heuristics now live inside the agent-owned tool implementation itself.

## Current Validation Path

The current runtime validation path is intentionally small and deterministic:

- `deterministic_tool` validates a local calculator tool call and finalizes a
  user-facing output
- `raise_error` proves the error hook and terminal failure reporting

This preserves the runtime-stage contract needed for later mixed
code-plus-LLM execution without forcing prompt building or provider transport
back into the kernel.

Prompt building, prompt-template choice, and profile-specific tool semantics
remain inside `Nexus`. Core Matrix computes and freezes the
conversation-visible tool set into `agent_context.allowed_tool_names`, and
`Nexus` enforces that frozen set at execution time when handling
`execute_tool`.

## Skill Surface

`Nexus` now keeps the skill boundary inside the agent rather
than pushing skills into `Core Matrix`.

Skill roots are separated intentionally:

- `skills/.system/<name>/` for reserved built-in `Nexus` skills
- `skills/.curated/<name>/` for bundled curated catalog entries
- `~/.nexus/skills-scopes/<agent_public_id>/<user_public_id>/live/<name>/` for installed third-party skills
- `~/.nexus/skills-scopes/<agent_public_id>/<user_public_id>/staging/<nonce>/<name>/` for staged installs
- `~/.nexus/skills-scopes/<agent_public_id>/<user_public_id>/backups/<timestamp>-<name>/` for replaced live backups

The current minimal skill surface is:

- `skills_catalog_list`
- `skills_load`
- `skills_read_file`
- `skills_install`

That surface is sufficient to:

- discover reserved system skills and bundled curated entries
- load one active system or installed skill body on demand
- read additional files relative to an active skill root
- stage and promote a third-party skill into the scoped live root

The default writable runtime home is `~/.nexus`. In host mode, `Nexus` stores:

- runtime skill state under `~/.nexus/skills-scopes/...`
- uv-managed Python under `~/.nexus/python`
- downloaded managed Python toolchains under `~/.nexus/toolchains/python`

In Docker or any other ephemeral runtime environment, set `NEXUS_HOME_ROOT`
to a persistent volume-backed path such as `/rails/storage/nexus-home` so
installed skills, the managed Python runtime, and downloaded Python toolchains
survive container replacement.

The current runtime keeps two explicit rules:

- `.system` skill names are reserved and may not be overridden
- installs become effective on the next top-level turn, not mid-turn

The built-in `deploy-agent` system skill exists to prove that `Nexus` can use
its own skill mechanism for an operational workflow, not just passive
instruction storage.

## Manual Acceptance Runtime Layout

The retained manual-acceptance layout uses one `Nexus` runtime base URL:

- `AGENT_NEXUS_PORT=3101 bin/dev`
  - default bundled/external runtime validation
  - dedicated skills-validation scenario execution
  - bundled mailbox execution
  - external pairing
  - deployment rotation
  - pairs with `bin/runtime-worker` for external mailbox execution and
    long-lived `ProcessRun` validation
  - `NEXUS_HOME_ROOT=/tmp/acceptance-nexus-home` in host validation
  - `NEXUS_HOME_ROOT=/rails/storage/nexus-home` inside docker validation

The skills-validation scenario keeps scoped skill writes out of the repo tree
by using a dedicated disposable `NEXUS_HOME_ROOT`, not a separate runtime port.
The manual acceptance scripts clear only that dedicated acceptance home root,
never a shared global live or staging root.

## Deployment Rotation

`Nexus` treats release change as deployment rotation:

- boot a new `Nexus` release as a new deployment
- expose the same manifest and mailbox control contract
- register it with Core Matrix
- cut future work over once the new deployment reaches healthy runtime
  participation

There is no in-place self-updater in the current runtime. Upgrade and downgrade are the
same kernel-facing operation.

## Distribution Contract

`Nexus` now documents one concrete distribution shape that matches the pairing
manifest:

- Docker on top of `images/nexus` is the default deployment path
- Ubuntu 24.04 is the canonical bare-metal host
- macOS remains a best-effort development environment

### Docker On `images/nexus`

Build the cowork runtime base first, then build the app image on top of it:

```bash
docker build -f images/nexus/Dockerfile -t nexus-local .
docker build --build-arg NEXUS_BASE_IMAGE=nexus-local:latest -f execution_runtimes/nexus/Dockerfile -t nexus-local execution_runtimes/nexus
```

For local container runs:

1. Copy [env.sample](/Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/env.sample) to `.env`
2. Fill in `CORE_MATRIX_AGENT_CONNECTION_CREDENTIAL` and either:
   - keep runtime secrets in the env file for container deployments, or
   - leave them blank and mount Rails credentials intentionally
3. Start the app image with `docker run --env-file ./.env -p 3101:80 nexus-local`
   - the Docker image defaults to `RAILS_ENV=production`

The app image intentionally owns only app-local responsibilities:

- copy source into `/rails`
- install gems from `Gemfile.lock`
- precompile bootsnap caches
- provide the Rails entrypoint and default server command

The broad cowork toolchain baseline lives in
[images/nexus](/Users/jasl/Workspaces/Ruby/cybros/images/nexus), not in the
`nexus` app image.

Key environment variables in the sample:

- `SECRET_KEY_BASE=...`
  - optional when Rails credentials already provide `secret_key_base`
  - `Nexus` resolves it through `Rails.app.creds`, which prefers ENV over the
    encrypted credentials file
  - for container deployments, prefer keeping it in the env file used by
    `docker run --env-file` or Compose `env_file`
- `ACTIVE_RECORD_ENCRYPTION__*`
  - optional when Rails credentials already provide
    `active_record_encryption.*`
  - for container deployments, keep them in the same env file as
    `SECRET_KEY_BASE`
- `NEXUS_PUBLIC_BASE_URL=http://localhost:3101`
  - the sample publishes the reachable manifest base URL explicitly
  - set this to the externally reachable origin when a reverse proxy or TLS
    terminator changes the public scheme/host/port
- `CORE_MATRIX_BASE_URL`
- `CORE_MATRIX_AGENT_CONNECTION_CREDENTIAL`
- `PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH=...`
  - optional bare-metal override when Chromium is not on `PATH`
- `NEXUS_DEV_PROXY_PORT=3310`
- `NEXUS_DEV_PROXY_ROUTES_FILE=/rails/tmp/dev-proxy/routes.caddy`

### Ubuntu 24.04 Bare Metal

The canonical bare-metal target is Ubuntu 24.04. Operators should:

- run [bin/check-runtime-host](/Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/bin/check-runtime-host)
- satisfy any missing prerequisites it reports
- provide `CORE_MATRIX_BASE_URL` and `CORE_MATRIX_AGENT_CONNECTION_CREDENTIAL`
- provide runtime secrets either through ENV or by populating Rails credentials
  with `bin/rails credentials:edit`
- start the Rails runtime and any app-local worker processes the deployment
  topology requires

### macOS Development Caveats

macOS is supported for development and validation, but not treated as the
canonical appliance baseline:

- run [bin/check-runtime-host](/Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/bin/check-runtime-host)
- satisfy any missing prerequisites it reports
- keep using `PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH` only when you intentionally
  want a non-default browser binary

## License

The `nexus` project is licensed under the O'Saasy License Agreement. See
[LICENSE.md](/Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/LICENSE.md).
