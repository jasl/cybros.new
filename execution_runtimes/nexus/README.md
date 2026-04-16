# Nexus

`nexus` is the default bundled execution runtime for Core Matrix.

Nexus is now an execution-runtime-only service. It owns runtime tool
execution, runtime-local resources, filesystem-backed skills, and
filesystem-backed memory. It does not assemble prompts, choose profiles, or
handle agent requests directly. Those responsibilities belong to
[agents/fenix](/Users/jasl/Workspaces/Ruby/cybros/agents/fenix).

## Monorepo Role

`execution_runtimes/nexus` is the active execution-runtime app in this
monorepo.

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

## Responsibilities

Nexus currently owns:

- execution-runtime mailbox handling
- command runs and detached processes
- browser sessions
- runtime-backed web and external tools
- filesystem-backed skill package access
- filesystem-backed memory storage

Nexus currently does not own:

- prompt assembly
- agent request execution
- profile selection
- supervision prompt behavior
- agent-owned deterministic tools

## Pairing Surface

Nexus exposes one pairing endpoint:

- `GET /runtime/manifest`

The manifest advertises:

- execution runtime identity and fingerprint
- protocol and SDK versions
- supported control-plane methods
- execution-runtime tool catalog
- runtime foundation metadata

The current pairing contract models Nexus as an execution-runtime-only
participant.

Core Matrix remains the orchestration source of truth and delivers runtime work
through the execution-runtime control plane:

- realtime push over `/cable`
- `POST /execution_runtime_api/control/poll` fallback delivery
- `POST /execution_runtime_api/control/report` for incremental reports back
  into the kernel

## Execution Surface

Nexus handles these mailbox request kinds:

- `execution_assignment`
- `resource_close_request`

Execution assignments currently dispatch into:

- runtime tool calls
- runtime-backed skill operations
- deterministic runtime validation helpers

The runtime reports progress through:

- `execution_started`
- `execution_progress`
- `execution_complete`
- `execution_fail`
- `process_started`
- `process_output`
- `process_exited`
- `resource_close_*`

## Tool Surface

The current runtime tool catalog is grouped into three runtime-owned operator
families:

- `command_run`
- `process_run`
- `browser_session`

Representative tools include:

- `exec_command`
- `write_stdin`
- `command_run_list`
- `process_exec`
- `process_list`
- `process_proxy_info`
- `browser_open`
- `browser_get_content`
- `browser_screenshot`

Filesystem-backed skills and memory are also runtime-owned here. Fenix can use
their materialized outputs, but Nexus is responsible for resolving them from
local storage.

Core Matrix composes the conversation-visible tool surface from
`ExecutionRuntime`, `Agent`, and `Core Matrix` catalogs in that precedence
order, then freezes `ToolBinding` rows before execution. Nexus only receives
execution assignments for bindings whose winning implementation source is the
execution runtime.

## Worker Topology

Nexus ships the worker entrypoints needed to stay connected to Core Matrix and
to manage long-lived runtime resources:

- `bin/rails runtime:control_loop_once`
- `bin/rails runtime:control_loop_forever`
- `bin/jobs start`
- `bin/runtime-worker`

The persistent worker is the owner of runtime-local handles such as detached
processes and browser sessions.

## Service Layout

Product services now live directly under `app/services`:

- `browser/`
- `memory/`
- `processes/`
- `runtime/`
- `shared/`
- `skills/`
- `tool_executors/`

There is no active `app/services/requests`, `app/services/prompts`, or
`build_round_instructions.rb` surface in Nexus.

## Deployment

Nexus is the heavy execution appliance in the default local stack:

- `core_matrix`
- `fenix`
- `nexus`

Multiple Nexus instances may be registered against one shared Fenix agent
service. That is the intended production shape when different machines or
workspaces need their own execution runtime.

An execution runtime is optional for a conversation. When no execution runtime
is selected, Nexus is simply not involved in that turn and Core Matrix routes
only agent-owned or Core Matrix-owned tool work.

The canonical host baseline comes from
[images/nexus](/Users/jasl/Workspaces/Ruby/cybros/images/nexus). Bare-metal
operators can validate the host toolchain with
[bin/check-runtime-host](/Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/bin/check-runtime-host).

## Multi-Arch Publishing

`execution_runtimes/nexus` inherits its multi-arch publishing behavior from
`NEXUS_BASE_IMAGE`. To publish `execution_runtimes/nexus` for both
`linux/amd64` and `linux/arm64`, the referenced base image must already be a
multi-arch manifest for those targets.

Example:

```bash
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  --build-arg NEXUS_BASE_IMAGE=ghcr.io/your-org/nexus-base:latest \
  -f execution_runtimes/nexus/Dockerfile \
  -t ghcr.io/your-org/nexus-runtime:latest \
  --push \
  execution_runtimes/nexus
```
