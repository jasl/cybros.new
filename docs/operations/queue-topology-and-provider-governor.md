# Queue Topology And Provider Governor

This document describes the baseline job topology for `core_matrix` and
`agents/fenix`, plus the knobs you can use to scale it beyond the default
4-core / 8GB development target.

## Baseline

The default configuration assumes:

- 4 CPU cores
- 8GB RAM
- multiple active conversations at the same time
- one queue worker process per queue class in development

The defaults are intentionally asymmetric:

- `llm_requests` is wider because it is mostly outbound network I/O
- `tool_calls` is also wide, but slightly narrower because tool work can be
  more bursty and may touch local resources
- orchestration and maintenance stay narrow
- `fenix` keeps registry-backed tools on a separate queue so operators can pin
  that queue to a small worker pool

## Core Matrix Queues

`core_matrix/config/queue.yml` defines four queues:

- `llm_requests`
- `tool_calls`
- `workflow_default`
- `maintenance`

Default thread and process counts:

- `llm_requests`: `SQ_THREADS_LLM=8`, `SQ_PROCESSES_LLM=1`
- `tool_calls`: `SQ_THREADS_TOOLS=6`, `SQ_PROCESSES_TOOLS=1`
- `workflow_default`: `SQ_THREADS_WORKFLOW=3`, `SQ_PROCESSES_WORKFLOW=1`
- `maintenance`: `SQ_THREADS_MAINTENANCE=1`, `SQ_PROCESSES_MAINTENANCE=1`

Routing rules:

- `turn_step` workflow nodes enqueue onto `llm_requests`
- `tool_call` workflow nodes enqueue onto `tool_calls`
- coordination and fallback work uses `workflow_default`
- lineage cleanup uses `maintenance`

## Fenix Queues

`agents/fenix/config/queue.yml` defines five queues:

- `runtime_prepare_round`
- `runtime_pure_tools`
- `runtime_process_tools`
- `runtime_control`
- `maintenance`

## Fenix Deployment Model

`fenix` is intentionally a single-machine deployment.

This is not just an operational preference. Right now `fenix` also acts as the
effective `ExecutionEnvironment`, which means it owns:

- worker-local command registries
- process and browser session handles
- runtime workspace side effects
- the queue workers that execute those resources

Because of that, the current design assumes one host owns the runtime state for
the installation. Do not treat `fenix` as a horizontally scaled stateless job
pool.

Operational rule:

- scale `fenix` up on one machine before considering any multi-host topology
- keep `runtime_process_tools` on that same machine
- if the deployment model changes in the future, first make registry-backed
  runtime ownership durable across hosts

Default thread and process counts:

- `runtime_prepare_round`: `SQ_THREADS_PREPARE=2`, `SQ_PROCESSES_PREPARE=1`
- `runtime_pure_tools`: `SQ_THREADS_PURE_TOOLS=6`, `SQ_PROCESSES_PURE_TOOLS=1`
- `runtime_process_tools`: `SQ_THREADS_PROCESS_TOOLS=2`, `SQ_PROCESSES_PROCESS_TOOLS=1`
- `runtime_control`: `SQ_THREADS_RUNTIME_CONTROL=2`, `SQ_PROCESSES_RUNTIME_CONTROL=1`
- `maintenance`: `SQ_THREADS_MAINTENANCE=1`, `SQ_PROCESSES_MAINTENANCE=1`
- `FENIX_DB_POOL=8`

Routing rules:

- `agent_program_request` with `request_kind=prepare_round` goes to `runtime_prepare_round`
- pure deterministic tools go to `runtime_pure_tools`
- registry-backed tools such as `exec_command`, `write_stdin`, `process_exec`,
  and browser session tools go to `runtime_process_tools`
- unmatched or control-like work falls back to `runtime_control`

Important operational note:

- keep `runtime_process_tools` narrow
- prefer one worker process for this queue
- treat extra threads as local concurrency on the same host, not as a signal
  that `fenix` should be spread across multiple hosts

## Provider Governor

`core_matrix` now has two independent throughput controls:

1. Queue concurrency in `config/queue.yml`
2. Provider admission control before the outbound HTTP request is sent

Provider governor defaults live in
[core_matrix/config/llm_catalog.yml](/Users/jasl/Workspaces/Ruby/cybros/core_matrix/config/llm_catalog.yml)
under each provider's `request_governor` block.

Example:

```yml
request_governor:
  max_concurrent_requests: 12
  throttle_limit: 600
  throttle_period_seconds: 60
```

Installation-specific overrides still live in `ProviderPolicy`:

- `max_concurrent_requests`
- `throttle_limit`
- `throttle_period_seconds`

Merge order:

- catalog defaults define the baseline
- `ProviderPolicy` overrides replace the catalog value when present

Behavior:

- requests above `max_concurrent_requests` are deferred before sending
- requests above `throttle_limit` in the configured window are deferred before sending
- upstream HTTP `429` responses create a cooldown and the job is retried later

## HTTPX

`core_matrix` uses `HTTPX` for provider traffic through `simple_inference`.
The default adapter now memoizes a persistent `HTTPX::Session` per process, so
steady-state traffic benefits from connection reuse.

What this does mean:

- repeated requests from the same worker process reuse persistent connections
- on `httpx 1.7.x`, the `:persistent` plugin also loads `:fiber_concurrency`
- the shared session remains safe to reuse across queue worker threads

What this does not mean:

- the app does not install a per-thread Ruby fiber scheduler today
- `turn_step` jobs still run as one request per ActiveJob execution, so there is
  no extra intra-thread fanout to multiplex
- if you later want scheduler-aware tuning, treat it as a separate rollout and
  measure it explicitly

## How To Scale Beyond 4 Cores

For a larger single host, widen queues first, then widen provider limits only
after observing live behavior.

Recommended order:

1. Increase `SQ_PROCESSES_LLM` or `SQ_THREADS_LLM`
2. Increase `SQ_PROCESSES_TOOLS` or `SQ_THREADS_TOOLS`
3. Increase `SQ_THREADS_PURE_TOOLS`
4. Only then raise provider governor concurrency for the specific provider

For a 32-core host, a safe first step is:

- double `llm_requests` worker processes
- double `tool_calls` worker processes
- keep `runtime_process_tools` at one process unless you have durable runtime ownership
- raise `openai` or `codex_subscription` provider caps from `12` to `16` or `20`
- watch `429` frequency, timeout rate, and queue depth before going higher

## 32-Core Single-Host Starter Profile

If you are running both `core_matrix` and `fenix` on a 32-core machine, start
with this profile before trying anything more aggressive.

### Core Matrix

```bash
export SQ_PROCESSES_LLM=3
export SQ_THREADS_LLM=12
export SQ_PROCESSES_TOOLS=2
export SQ_THREADS_TOOLS=8
export SQ_PROCESSES_WORKFLOW=2
export SQ_THREADS_WORKFLOW=4
export SQ_PROCESSES_MAINTENANCE=1
export SQ_THREADS_MAINTENANCE=2
```

Why this shape:

- `llm_requests` gets the widest pool because it is mostly outbound I/O
- `tool_calls` is wide, but not as wide as `llm_requests`
- workflow coordination stays moderate so it does not starve the two hot queues
- maintenance stays small

### Fenix

```bash
export SQ_PROCESSES_PREPARE=1
export SQ_THREADS_PREPARE=4
export SQ_PROCESSES_PURE_TOOLS=2
export SQ_THREADS_PURE_TOOLS=8
export SQ_PROCESSES_PROCESS_TOOLS=1
export SQ_THREADS_PROCESS_TOOLS=4
export SQ_PROCESSES_RUNTIME_CONTROL=1
export SQ_THREADS_RUNTIME_CONTROL=4
export SQ_PROCESSES_MAINTENANCE=1
export SQ_THREADS_MAINTENANCE=1
export FENIX_DB_POOL=10
```

Why this shape:

- `runtime_pure_tools` can widen because it does not own durable process state
- `runtime_process_tools` stays on one process because `fenix` is single-host
  and registry-backed
- `runtime_prepare_round` and `runtime_control` can widen a bit without taking
  over the machine

### Provider Governor On 32 Cores

Do not treat provider limits as a direct mirror of CPU count. Increase provider
concurrency based on queue capacity and observed provider behavior, not just on
host size.

Recommended starting rule:

- start `max_concurrent_requests` at roughly 50% to 60% of total
  `llm_requests` thread capacity on the host
- on the profile above, `SQ_PROCESSES_LLM=3` and `SQ_THREADS_LLM=12` gives a
  total of `36` LLM worker threads, so a good starting window is `18` to `22`
- keep `throttle_limit` conservative until you confirm the provider quota can
  actually sustain a higher request rate

Reasonable first overrides for a 32-core single host:

- `codex_subscription`: `max_concurrent_requests=20`
- `openai`: `max_concurrent_requests=20`
- `openrouter`: `max_concurrent_requests=12`
- `dev`: `max_concurrent_requests=8`
- `local`: tune against the actual local model server, not the CPU count alone

Increase beyond this only if:

- queue depth remains healthy
- request timeout rate stays flat
- upstream `429` responses remain rare
- memory pressure stays under control

Back off quickly if:

- `llm_requests` queue depth improves but `429` rises sharply
- `tool_calls` starts waiting behind saturated `llm_requests`
- `runtime_process_tools` latency spikes on `fenix`
- process RSS growth becomes the limiting factor instead of CPU

## How To Apply Local Changes

You normally do not edit `queue.yml` itself for host-specific tuning. Keep the
checked-in files as the baseline profile, then set environment variables in
your deployment layer.

Typical workflow:

1. Set the `SQ_*` environment variables for the host or container.
2. Restart the Solid Queue worker processes.
3. Observe queue depth, job latency, timeout rate, and `429` frequency.
4. Only then adjust provider governor values.

For provider overrides, prefer using `ProviderPolicy` over editing the catalog
unless you really want to change the installation-wide default baseline.

## Tuning Checklist

When changing throughput:

- change queue env vars first
- restart queue workers
- verify queue depth and job latency
- then adjust provider governor values
- verify provider error rate, especially `429`
- keep `runtime_process_tools` conservative

## Files To Edit

- [core_matrix/config/queue.yml](/Users/jasl/Workspaces/Ruby/cybros/core_matrix/config/queue.yml)
- [core_matrix/config/llm_catalog.yml](/Users/jasl/Workspaces/Ruby/cybros/core_matrix/config/llm_catalog.yml)
- [agents/fenix/config/queue.yml](/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/config/queue.yml)
- [core_matrix/app/models/provider_policy.rb](/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/models/provider_policy.rb)
