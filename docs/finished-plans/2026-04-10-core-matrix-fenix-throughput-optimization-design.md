# CoreMatrix/Fenix Throughput Optimization Design

**Date:** 2026-04-10

## Goal

Improve throughput and heavy-load latency for the `1 CoreMatrix + 8 Fenix` topology without changing the Rails/Solid Queue/PostgreSQL/SQLite stack.

## Current Findings

Verified local baselines show:

- `target_8_fenix` is healthy and stable, but `turn_latency.p95_ms` remains around seven seconds even for the lighter queued runtime-control profile.
- `stress` completes all work but shows high tail latency and queue delay.
- `database_checkout_pressure.timeout_count` stays `0` and checkout waits remain tiny.

The system is not database-bound first. The dominant costs are:

1. worker threads held by synchronous `AgentRequestExchange` receipt polling
2. mailbox routing work repeated in the `Poll` hot path
3. queue-family contention between heavy execution and lightweight orchestration

## Design Direction

### 1. Make agent mailbox requests resumable instead of synchronously blocking

`ProviderExecution::AgentRequestExchange` currently creates a mailbox request and then holds a worker thread while polling `AgentControlReportReceipt`.

We will replace that model with:

- create mailbox request
- persist workflow wait state on the current `WorkflowNode`
- release the worker thread immediately
- when the terminal agent report arrives, resume the blocked workflow step

This keeps worker threads doing useful work instead of sleeping on receipt polling.

### 2. Materialize delivery routing so `Poll` is a lease path, not a resolution engine

`AgentControl::Poll` currently resolves runtime delivery targets dynamically for candidate items. Under load, that makes a very hot path perform repeated routing work.

We will add explicit materialized routing data to mailbox items so poll can:

- select items already known to target the current runtime
- lease them
- emit lease events

without repeated runtime-target recomputation.

### 3. Separate heavy execution from orchestration queues

Current queue topology still allows heavy provider/exchange work and lightweight workflow orchestration to share too much of the same capacity envelope.

We will:

- raise local/dev provider concurrency where it is clearly under-provisioned
- introduce an explicit lightweight orchestration/resume queue
- keep heavy provider/tool execution on separate queues

This should reduce head-of-line blocking and improve tail latency under stress.

## Scope

### In scope

- CoreMatrix runtime topology and queue defaults
- mailbox item routing materialization
- workflow wait/resume behavior for agent requests
- report-handling follow-up that resumes blocked workflow work
- acceptance/perf gates and docs updates

### Out of scope

- changing database engines
- changing job backends away from Solid Queue
- changing Fenix transport protocol shape at the external API boundary
- CI hard budgets for perf thresholds

## Architecture Notes

### Workflow waiting model

We will reuse the existing workflow wait system instead of introducing a second async execution state machine.

Primary reusable pieces:

- `WorkflowRun.waiting`
- `WorkflowNode.waiting`
- `Workflows::ResumeBlockedStep`
- `Workflows::ResumeAfterWaitResolution`
- report follow-up hooks in `AgentControl`

### Routing model

Mailbox routing should become an explicit infrastructure concern on `AgentControlMailboxItem`, not an emergent behavior reconstructed on each poll.

The preferred end state is:

- mailbox item creation determines the intended control-plane target
- poll only filters and leases items already addressed to the current runtime

### Queue model

We will preserve Solid Queue, but the topology will become more intentional:

- provider-heavy queues
- tool/runtime execution queues
- lightweight orchestration/resume queues
- maintenance

## Acceptance

The optimization is complete when:

- correctness tests still pass across `agents/fenix`, `core_matrix`, `simple_inference`, Docker verifies, and acceptance suites
- `target_8_fenix` and `stress` still pass their local gates
- heavy-load tail latency and queue delay improve measurably versus the current April 10 baseline
- no new fake or shortcut implementation remains in the mailbox-exchange path
- documentation reflects the new runtime and queue semantics
