# Fenix

`fenix` is the default bundled agent for Core Matrix.

Fenix is now an agent-only service. It owns prompt assembly, agent-owned tools,
and agent mailbox handling. It does not execute runtime tools, manage detached
processes, host browser sessions, or persist filesystem-backed skills or
memory. Those responsibilities belong to
[execution_runtimes/nexus](/Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus).

## Monorepo Role

`agents/fenix` is the active cowork app for the bundled agent in this monorepo.

- active agent/product work lands in `agents/fenix`
- the default bundled execution runtime lives in `execution_runtimes/nexus`

## Verification

Run the documented project checks from the app directory:

```bash
cd agents/fenix
bin/brakeman --no-pager
bin/bundler-audit
bin/rubocop -f github
bin/rails db:test:prepare
bin/rails test
```

## Responsibilities

Fenix currently owns:

- agent prompt assembly
- agent mailbox request handling
- agent-owned deterministic tools
- profile and subagent defaults
- supervision-oriented agent behaviors

Fenix currently does not own:

- execution-runtime tool execution
- command runs or detached processes
- browser sessions
- filesystem-backed skill repositories
- filesystem-backed memory storage

When a turn needs runtime-backed context such as skills or memory, Core Matrix
freezes and forwards those materials into the agent request payload. Fenix
consumes `memory_context` and `skill_context`; it does not resolve them from
the local filesystem.

## Pairing Surface

Fenix exposes one pairing endpoint:

- `GET /runtime/manifest`

The manifest advertises:

- agent identity and fingerprint
- protocol and SDK versions
- supported control-plane methods
- agent-owned tool catalog
- profile policy
- agent-plane canonical config surfaces

The current pairing contract models Fenix as an agent-only participant.

Core Matrix remains the orchestration source of truth and delivers agent work
through the agent control plane:

- realtime push over `/cable`
- `POST /agent_api/control/poll` fallback delivery
- `POST /agent_api/control/report` for incremental reports back into the kernel

## Agent Request Surface

Fenix handles these mailbox request kinds:

- `prepare_round`
- `execute_tool`
- `supervision_status_refresh`
- `supervision_guidance`

Agent-owned tools are intentionally small:

- `compact_context`

Runtime-backed tool names can still appear in `agent_context.allowed_tool_names`
because Core Matrix freezes the conversation-visible tool set for the turn.
Fenix may reference those names in prompts, but it does not execute them
locally.

Core Matrix composes the conversation-visible tool surface from
`ExecutionRuntime`, `Agent`, and `Core Matrix` catalogs in that precedence
order, then freezes `ToolBinding` rows before execution. Fenix only receives
`execute_tool` requests for bindings whose winning implementation source is the
agent.

## Worker Topology

Fenix ships the same mailbox worker entrypoints as the rest of the platform,
but they operate only on agent-plane work:

- `bin/rails runtime:control_loop_once`
- `bin/rails runtime:control_loop_forever`
- `bin/jobs start`
- `bin/runtime-worker`

Long-lived runtime handles are not retained here anymore. The persistent worker
exists to keep the agent control-plane connection healthy and to settle
agent-owned close requests such as agent task runs or subagent connections.

## Service Layout

Product services now live directly under `app/services`:

- `build_round_instructions.rb`
- `hooks/`
- `prompts/`
- `requests/`
- `runtime/`
- `shared/`

There is no active `app/services/execution_runtime` tree in Fenix.

## Deployment

Fenix is deployed as a lightweight agent service and is intended to run
alongside Core Matrix plus one or more execution runtimes.

The heavy runtime/toolchain baseline lives in `images/nexus`, documented at
[images/nexus](/Users/jasl/Workspaces/Ruby/cybros/images/nexus), not in the
Fenix app image.

The default local stack is:

- `core_matrix`
- `fenix`
- `nexus`

Fenix pairs with Core Matrix using `CORE_MATRIX_BASE_URL` and
`CORE_MATRIX_AGENT_CONNECTION_CREDENTIAL`. Execution happens through the
selected execution runtime rather than inside the Fenix container or host.

An execution runtime is optional at conversation time. When no execution
runtime is selected and no default execution runtime is available, Fenix can
still drive agent-only conversations with prompt assembly plus any
agent-owned or Core Matrix-owned tools that remain visible after profile
policy masking.

## License

`agents/fenix` is licensed under the MIT License. See
[LICENSE.txt](/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/LICENSE.txt).
