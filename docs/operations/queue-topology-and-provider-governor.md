# Queue Topology And Provider Governor

This document describes the phase2 runtime topology for `core_matrix` and
`agents/fenix`.

The design is intentionally not backwards-compatible with the transitional
`llm_requests` setup. Queue routing, provider admission control, and Fenix pool
defaults now come from explicit topology definitions and should be tuned as
such.

## Baseline

The checked-in defaults target:

- 4 CPU cores
- 8GB RAM
- multiple active conversations on one host

## Core Matrix

`core_matrix/config/runtime_topology.yml` is the source of truth for worker
topology. `core_matrix/config/queue.yml` is now a render target for that file.

### Queues

- `llm_codex_subscription`: `SQ_THREADS_LLM_CODEX_SUBSCRIPTION=2`, `SQ_PROCESSES_LLM_CODEX_SUBSCRIPTION=1`
- `llm_openai`: `SQ_THREADS_LLM_OPENAI=3`, `SQ_PROCESSES_LLM_OPENAI=1`
- `llm_openrouter`: `SQ_THREADS_LLM_OPENROUTER=2`, `SQ_PROCESSES_LLM_OPENROUTER=1`
- `llm_dev`: `SQ_THREADS_LLM_DEV=1`, `SQ_PROCESSES_LLM_DEV=1`
- `llm_local`: `SQ_THREADS_LLM_LOCAL=1`, `SQ_PROCESSES_LLM_LOCAL=1`
- `tool_calls`: `SQ_THREADS_TOOL_CALLS=6`, `SQ_PROCESSES_TOOL_CALLS=1`
- `workflow_default`: `SQ_THREADS_WORKFLOW_DEFAULT=3`, `SQ_PROCESSES_WORKFLOW_DEFAULT=1`
- `maintenance`: `SQ_THREADS_MAINTENANCE=1`, `SQ_PROCESSES_MAINTENANCE=1`

### Routing

- `turn_step` nodes route to `llm_<resolved_provider_handle>`
- `tool_call` nodes route to `tool_calls`
- workflow coordination routes to `workflow_default`
- maintenance stays on `maintenance`

### Provider Admission Control

`core_matrix/config/llm_catalog.yml` now owns provider-side throughput defaults
through `admission_control` blocks.

Example:

```yml
admission_control:
  max_concurrent_requests: 4
  cooldown_seconds: 15
```

Behavior:

- `max_concurrent_requests` is the hard per-installation cap for active requests
- upstream `429` responses move the provider into cooldown
- cooldown duration uses `Retry-After` when present, else `cooldown_seconds`
- state is durable in the database, not in cache

Operational tables:

- `provider_request_controls`
- `provider_request_leases`

`ProviderPolicy` no longer carries concurrency or throttle fields. It only
controls enablement and selection defaults.

### HTTPX

`core_matrix/vendor/simple_inference` still uses persistent `HTTPX` sessions.
That gives connection reuse and fiber-compatible transport behavior, but the
runtime model is still one ActiveJob per outbound request. Do not assume an
extra throughput tier from Ruby fiber scheduler rollout.

## Fenix

`fenix` is intentionally single-host today because it also acts as the
effective `ExecutionEnvironment` and owns registry-backed runtime state.

This assumption is now explicit in code and docs. Scale it up on one machine;
do not treat it as a stateless horizontal worker pool.

`agents/fenix/config/runtime_topology.yml` is the source of truth for:

- queue names
- worker defaults
- database pool defaults

### Queues

- `runtime_prepare_round`: `SQ_THREADS_PREPARE=2`, `SQ_PROCESSES_PREPARE=1`
- `runtime_pure_tools`: `SQ_THREADS_PURE_TOOLS=6`, `SQ_PROCESSES_PURE_TOOLS=1`
- `runtime_process_tools`: `SQ_THREADS_PROCESS_TOOLS=2`, `SQ_PROCESSES_PROCESS_TOOLS=1`
- `runtime_control`: `SQ_THREADS_RUNTIME_CONTROL=2`, `SQ_PROCESSES_RUNTIME_CONTROL=1`
- `maintenance`: `SQ_THREADS_MAINTENANCE=1`, `SQ_PROCESSES_MAINTENANCE=1`

Routing:

- `prepare_round` requests go to `runtime_prepare_round`
- deterministic, non-registry tools go to `runtime_pure_tools`
- registry-backed tools such as `exec_command`, `write_stdin`, process, and browser session tools go to `runtime_process_tools`
- unmatched control work goes to `runtime_control`

Operationally, the persistent mailbox control loop is not sufficient by itself
when `Fenix` runs with `solid_queue`. External runtime instances must also run
the local queue workers under the same `CORE_MATRIX_BASE_URL` and
`CORE_MATRIX_MACHINE_CREDENTIAL`, either as `bin/jobs start` plus
`bin/rails runtime:control_loop_forever` or via `bin/runtime-worker`.

Run exactly one such worker set per Dockerized `Fenix` runtime. Registry-backed
browser sessions, command handles, and process handles are in-memory local
state; starting a second `bin/runtime-worker` or a second `bin/jobs start`
against the same runtime splits that state across multiple worker pools and can
surface `unknown ... session/run` validation failures on follow-up tool calls.

### Database Pools

`agents/fenix/config/database.yml` now uses explicit pools:

- `FENIX_PRIMARY_DB_POOL=5`
- `FENIX_QUEUE_DB_POOL=8`

Raise them independently. Do not rely on derived pool math anymore.

## 32-Core Single-Host Starter Profile

Use this as a starting point, not an endpoint.

### Core Matrix

```bash
export SQ_THREADS_LLM_CODEX_SUBSCRIPTION=6
export SQ_PROCESSES_LLM_CODEX_SUBSCRIPTION=1
export SQ_THREADS_LLM_OPENAI=8
export SQ_PROCESSES_LLM_OPENAI=2
export SQ_THREADS_LLM_OPENROUTER=4
export SQ_PROCESSES_LLM_OPENROUTER=1
export SQ_THREADS_LLM_DEV=2
export SQ_PROCESSES_LLM_DEV=1
export SQ_THREADS_LLM_LOCAL=2
export SQ_PROCESSES_LLM_LOCAL=1
export SQ_THREADS_TOOL_CALLS=8
export SQ_PROCESSES_TOOL_CALLS=2
export SQ_THREADS_WORKFLOW_DEFAULT=4
export SQ_PROCESSES_WORKFLOW_DEFAULT=2
export SQ_THREADS_MAINTENANCE=2
export SQ_PROCESSES_MAINTENANCE=1
```

Raise provider caps only after queue depth, timeout rate, and `429` rate are
stable.

Suggested first-step admission control ceilings:

- `codex_subscription`: `max_concurrent_requests=10`
- `openai`: `max_concurrent_requests=12`
- `openrouter`: `max_concurrent_requests=6`
- `dev`: `max_concurrent_requests=4`

### Fenix

```bash
export SQ_THREADS_PREPARE=4
export SQ_PROCESSES_PREPARE=1
export SQ_THREADS_PURE_TOOLS=8
export SQ_PROCESSES_PURE_TOOLS=2
export SQ_THREADS_PROCESS_TOOLS=4
export SQ_PROCESSES_PROCESS_TOOLS=1
export SQ_THREADS_RUNTIME_CONTROL=4
export SQ_PROCESSES_RUNTIME_CONTROL=1
export SQ_THREADS_MAINTENANCE=1
export SQ_PROCESSES_MAINTENANCE=1
export FENIX_PRIMARY_DB_POOL=8
export FENIX_QUEUE_DB_POOL=12
```

Keep `runtime_process_tools` conservative unless the registry-backed runtime
state model changes.
