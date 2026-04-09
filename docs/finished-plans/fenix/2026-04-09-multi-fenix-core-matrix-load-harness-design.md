# Multi-Fenix CoreMatrix Load Harness Design

## Goal

Add a reproducible system-level load harness that exercises one `CoreMatrix`
instance coordinating multiple `Fenix` runtimes at once, with first-class
benchmark artifacts for:

- throughput
- turn latency
- control-plane poll latency
- mailbox lease latency
- mailbox exchange wait
- queue pressure
- database checkout pressure

The harness must tell us whether "8 Fenix deployments against 1 CoreMatrix"
fails because of CoreMatrix control-plane pressure, CoreMatrix queue pressure,
Fenix runtime pressure, database starvation, or some combination of them.

## Problem

The current repo has two useful but incomplete kinds of concurrency coverage:

- `agents/fenix` now has real runtime-parallel and queue-topology tests
- `core_matrix` now has queue/Puma/database baseline contract tests

Those are necessary, but they do not answer the system question that matters
for rollout:

> when several real Fenix runtimes connect to the same CoreMatrix, where does
> the shared system actually saturate?

Today we do not have a benchmark harness that can:

- boot multiple independent Fenix runtimes against one CoreMatrix
- drive concurrent conversations across those runtimes
- collect cross-process performance evidence into one artifact bundle
- distinguish product regressions from environment or provider noise

## Decision

Do **not** create a new top-level `benchmark/` or `benchmarks/` project yet.

Instead:

- keep benchmark orchestration inside the top-level [`acceptance`](/Users/jasl/Workspaces/Ruby/cybros/acceptance) harness
- keep benchmark semantics and workload definitions inside `acceptance`
- add only neutral, optional telemetry hooks inside
  [`core_matrix`](/Users/jasl/Workspaces/Ruby/cybros/core_matrix) and
  [`agents/fenix`](/Users/jasl/Workspaces/Ruby/cybros/agents/fenix)

This keeps the repo aligned with its current boundaries:

- `acceptance` owns cross-product orchestration and artifact packaging
- `core_matrix` remains agent-program-neutral
- `agents/fenix` remains runtime-local and product-specific

## Options Considered

### Option 1: New top-level benchmark project

Pros:

- isolated toolchain
- easy to grow into a dedicated load lab later

Cons:

- duplicates stack boot, artifact packaging, and benchmark reporting that
  already exist in `acceptance`
- creates a second orchestration surface before the first one is exhausted
- increases monorepo surface area for a problem that is still acceptance-shaped

### Option 2: Acceptance-embedded system load harness

Pros:

- reuses the existing stack boot path, scenario model, and artifact bundle
- keeps benchmark semantics out of product apps
- easiest path to a real end-to-end benchmark soon

Cons:

- acceptance gains another sub-domain
- requires careful layering so harness logic does not leak into products

### Option 3: External HTTP-only load driver

Pros:

- lowest product-code touch
- easy to push raw request volume

Cons:

- does not exercise the actual external-runtime pairing model
- cannot see mailbox lease, poll, or runtime queue behavior cleanly
- too far from the real "many Fenix against one CoreMatrix" topology

### Recommendation

Choose **Option 2** now. Revisit a top-level `benchmarks/` project only if
this grows into a separate long-running toolchain with distinct dependencies,
external dashboards, or non-acceptance execution models.

## Non-Goals

This phase does **not** aim to:

- introduce Prometheus, StatsD, OpenTelemetry, or another persistent monitoring
  stack
- make benchmark telemetry part of user-facing product features
- encode benchmark-specific semantics in `core_matrix` or `agents/fenix`
- replace the existing 2048 capstone
- set permanent performance SLO thresholds before we have one clean baseline

## Constraints

### 1. Acceptance owns benchmark semantics

Workload names, pass/fail thresholds, scenario profiles, and artifact bundle
structure belong in `acceptance`, not in either product app.

### 2. CoreMatrix remains neutral

Any CoreMatrix instrumentation added for this harness must stay:

- agent-program-neutral
- capability-optional
- semantically generic

It may describe events like "poll completed" or "mailbox item leased". It must
not know about "8 Fenix benchmark mode".

### 3. Fenix remains runtime-local

Fenix may expose runtime-local telemetry about its own poll, queue, and mailbox
execution paths, but it must not own global benchmark orchestration.

### 4. Use public ids at external boundaries

Any benchmark artifact that leaves a product process must use public ids or
generic string identifiers, never bigint internals.

### 5. Benchmark telemetry must be low-perturbation

If telemetry collection writes large volumes back into the main app database, it
will distort the benchmark itself. High-frequency benchmark telemetry must not
depend on new DB writes in the hot path.

## Proposed Architecture

## 1. Acceptance-Centric Load Harness

Add a new acceptance scenario family dedicated to system load:

- [`acceptance/scenarios/multi_fenix_core_matrix_load_validation.rb`](/Users/jasl/Workspaces/Ruby/cybros/acceptance/scenarios/multi_fenix_core_matrix_load_validation.rb)

That scenario will:

- boot one CoreMatrix
- boot `N` independent Fenix runtimes
- register each runtime as its own external agent-program deployment
- create and drive a workload across those deployments
- collect benchmark artifacts
- emit a machine-readable summary and a short human-readable review index

### Why independent external agent programs?

For `v1`, model each Fenix deployment as its own external agent program. That
matches the current pairing and registration flow cleanly and avoids mixing
"multi runtime" questions with "one program version, many sessions" questions.

The first benchmark topology should therefore be:

- one disposable installation per benchmark run
- one CoreMatrix
- `N` external Fenix agent programs
- one runtime registration per program
- multiple conversations distributed round-robin across those programs

We can add "many sessions for one program version" as a later profile if it
becomes important.

## 2. Run Isolation

Each benchmark run must be disposable and isolated from prior runs.

The harness must create a fresh run root that owns:

- one disposable acceptance artifact root
- one disposable `FENIX_HOME_ROOT` per runtime slot
- one event file per process
- one reset CoreMatrix state baseline before workload starts

The harness must not reuse runtime home directories, event files, or leftover
artifact directories across benchmark runs. If a previous run leaves residue,
the new run should fail fast or clean it first.

## 3. Benchmark Profiles

The harness should support explicit named profiles instead of one ad-hoc load
mode.

### `smoke`

Purpose:

- prove the harness wiring works in CI or local quick checks

Shape:

- `2` Fenix runtimes
- `2-4` concurrent conversations
- deterministic or very low-variance workload only

### `target_8_fenix`

Purpose:

- baseline the intended rollout shape

Shape:

- `8` Fenix runtimes
- fixed concurrency per runtime
- steady-state run long enough to expose queue and lease pressure

### `stress`

Purpose:

- deliberately push beyond target capacity and observe degradation shape

Shape:

- `8` Fenix runtimes
- higher conversation fan-out
- longer steady-state window

### `provider_mixed` (follow-up, not first gate)

Purpose:

- add provider variance and real tool/provider mix after the control-plane-only
  harness is trusted

The first implementation should gate on `smoke` and `target_8_fenix`, not on a
provider-heavy profile.

## 4. Workload Model

The benchmark workload must be deterministic enough to compare runs, but rich
enough to exercise the real CoreMatrix <-> Fenix control loop.

### Initial v1 workload

Use a deterministic mailbox/task workload first.

Properties:

- exercises external runtime registration
- exercises mailbox lease and delivery
- exercises Fenix runtime queue execution
- avoids provider latency dominating the benchmark

The first profile should not depend on third-party provider availability.

The concrete v1 workload should be intentionally narrow:

- create one conversation per scheduled workload slot
- submit one deterministic mailbox turn at a time per conversation
- use a fixed corpus of simple deterministic requests such as arithmetic or
  echo-style tool payloads
- keep workspace and browser work out of `smoke` and `target_8_fenix`
- record per-workload-item start time, target runtime label, completion time,
  and completion status
- reuse the existing deterministic external mailbox/task path instead of
  inventing a benchmark-only runtime mode

This keeps the first benchmark focused on shared control-plane and runtime
pressure instead of application-specific task variance.

### Follow-up workload

After the control-plane harness is stable, add a second profile that mixes in a
provider-backed turn. That profile should remain informative, but it should not
be the first or only benchmark gate because provider variance will blur the
signal.

## 5. Telemetry Strategy

Use a two-step telemetry design:

1. product apps emit neutral in-process events
2. an optional benchmark-only sink writes those events to NDJSON files

### Why not write benchmark telemetry to the product DB?

Because:

- the event volume can be high
- DB writes in the hot path would distort the benchmark
- the benchmark wants transient evidence, not product truth

### Product-side event model

Both `core_matrix` and `agents/fenix` should emit neutral event payloads such
as:

- event name
- recorded time
- duration, when relevant
- success/failure
- queue name, when relevant
- public ids for installation/user/workspace/conversation/turn/program/session
  when relevant
- small metadata hash

### Benchmark sink

Add an optional, disabled-by-default event sink in each app, enabled only when
the acceptance harness sets benchmark env vars such as:

- `CYBROS_PERF_EVENTS_PATH`
- `CYBROS_PERF_INSTANCE_LABEL`

The sink should:

- subscribe to selected in-process events
- append one JSON object per line to the configured file
- avoid retries, buffering complexity, or cross-process aggregation
- never activate unless explicitly configured

### NDJSON schema

Each line should contain:

- `recorded_at`
- `source_app`
- `instance_label`
- `event_name`
- `duration_ms`
- `success`
- `installation_public_id`
- `user_public_id`
- `workspace_public_id`
- `conversation_public_id`
- `turn_public_id`
- `agent_program_public_id`
- `agent_session_public_id`
- `executor_session_id`
- `queue_name`
- `metadata`

All ids must be public ids or generic runtime string ids, never bigint
internals.

## 6. Metrics To Capture

The first benchmark summary should calculate these metrics.

### Throughput

- completed turns per minute
- completed mailbox items per minute
- completed workload items per runtime

### Turn Latency

- end-to-end turn duration
- `p50`, `p95`, `p99`, and max

### Poll Latency

- Fenix-side control-plane poll duration
- CoreMatrix-side poll request handling duration

This helps separate network/transport delay from CoreMatrix-side request delay.

### Mailbox Lease Latency

- time from mailbox item creation to lease grant

This reveals queueing pressure or lease starvation at the control plane.

### Mailbox Exchange Wait

- time spent in `ProgramMailboxExchange` waiting for terminal receipt

This is one of the most important shared-system pressure signals because it
captures how long CoreMatrix waits for the runtime loop to return a settled
result.

### Queue Pressure

For both products, capture:

- queue backlog snapshots
- job start delay / enqueue-to-perform delay where available
- max observed backlog during the run

### Database Checkout Pressure

Capture:

- checkout wait duration
- timeout count
- periodic pool snapshots (`size`, `connections`, `busy`, `idle`, `dead`,
  `waiting`) where available

This is the main early-warning signal for DB starvation under widened queue
topologies.

## 7. Where To Instrument

### CoreMatrix

Instrument the hot paths that reflect shared-system pressure:

- agent control poll handling
- mailbox lease grant
- `ProviderExecution::ProgramMailboxExchange`
- queue execution start/completion for the queues we widened
- DB checkout pressure

### Fenix

Instrument the hot paths that reflect runtime-side pressure:

- control-plane poll round trip
- runtime mailbox execution start/completion
- runtime queue execution start/completion
- DB checkout pressure

### Acceptance

Acceptance owns:

- workload generation
- artifact merge
- metric aggregation
- pass/fail evaluation

It should not infer system metrics from product logs alone if those metrics can
be captured directly.

## 8. Artifact Layout

Reuse the existing acceptance artifact shape.

For the new load scenario, the bundle should include:

- `review/index.md`
- `review/load-summary.md`
- `evidence/run-summary.json`
- `evidence/workload-profile.json`
- `evidence/aggregated-metrics.json`
- `evidence/core-matrix-events.ndjson`
- `evidence/fenix-01-events.ndjson` through `fenix-08-events.ndjson`
- `evidence/runtime-topology.json`
- `logs/` with stack logs

The run summary should clearly separate:

- benchmark configuration
- outcome
- structural failures
- capacity symptoms
- strongest bottleneck indicators

## 9. Pass/Fail Model

Do not start with arbitrary hard latency thresholds.

### Phase 1 outcome model

The first version should fail only on structural conditions such as:

- one or more runtimes failed to boot or register
- workload items did not complete as expected
- severe mailbox lease failures or timeouts occurred
- benchmark artifacts are incomplete

The summary should still report all measured latencies and pressure metrics, but
those should be descriptive first.

### Phase 2 outcome model

After one or two clean local baselines, add explicit thresholds for:

- p95 turn latency
- p95 poll latency
- max mailbox lease latency
- queue backlog ceiling
- DB checkout timeout count

## 10. CI And Execution Model

Do not run the full 8-Fenix target profile on every CI job immediately.

Recommended execution split:

- CI:
  - `smoke`
- local/manual benchmark:
  - `target_8_fenix`
- optional scheduled/overnight:
  - `stress`

This keeps normal CI bounded while still giving us a real benchmark gate and a
heavier manual diagnostic path.

## 11. Why This Should Live In `acceptance`

This design keeps concerns orthogonal:

- `acceptance` owns workload semantics and artifact bundles
- `core_matrix` owns neutral orchestration and optional telemetry hooks
- `agents/fenix` owns runtime-local telemetry hooks

That is the cleanest shape for a monorepo benchmark at this stage.

If the harness later grows into:

- a distinct toolchain
- external dashboards
- non-acceptance execution paths
- language/runtime dependencies that do not belong in acceptance

then a future top-level `benchmarks/` project will make sense. It does not make
sense yet.

## 12. Implementation Shape

The matching implementation plan should:

1. add acceptance-side topology/profile primitives
2. add optional NDJSON event sinks to CoreMatrix and Fenix
3. instrument the required neutral events
4. add the multi-runtime activation/orchestration path
5. build the metric aggregator and artifact bundle
6. add smoke and target benchmark scenarios
7. keep CI on a smoke profile only
