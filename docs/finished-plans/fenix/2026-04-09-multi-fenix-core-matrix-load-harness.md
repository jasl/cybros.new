# Multi-Fenix CoreMatrix Load Harness Implementation Plan

**Goal:** Build an acceptance-embedded system load harness that can run one `CoreMatrix` against multiple `Fenix` runtimes, collect low-perturbation performance evidence, and report where shared-system pressure appears first.

**Architecture:** Keep workload semantics, topology profiles, and benchmark summaries in `acceptance`. Add only neutral, optional telemetry hooks to `core_matrix` and `agents/fenix`, with benchmark-only NDJSON sinks enabled by environment variables. Start with deterministic workload profiles and smoke/target runs, then add heavier or provider-backed profiles later.

**Tech Stack:** top-level acceptance Ruby harness, Rails 8 apps (`core_matrix`, `agents/fenix`), Minitest, optional `ActiveSupport::Notifications`-driven event sinks, NDJSON artifact logs, Docker runtime activation scripts.

---

## Task 1: Add acceptance-side benchmark profile and topology primitives

**Files:**

- Create: `acceptance/lib/perf/profile.rb`
- Create: `acceptance/lib/perf/topology.rb`
- Create: `acceptance/lib/perf/workload_manifest.rb`
- Create: `test/acceptance/perf/profile_test.rb`
- Create: `test/acceptance/perf/topology_test.rb`
- Create: `test/acceptance/perf/workload_manifest_test.rb`

**Steps:**

1. Write failing tests for:
   - valid profile names (`smoke`, `target_8_fenix`, `stress`)
   - valid runtime counts per profile
   - deterministic port and container naming per runtime slot
   - deterministic workload manifest defaults for the first benchmark profiles
2. Run:
   - `cd /Users/jasl/Workspaces/Ruby/cybros && ruby test/acceptance/perf/profile_test.rb`
   - `cd /Users/jasl/Workspaces/Ruby/cybros && ruby test/acceptance/perf/topology_test.rb`
   - `cd /Users/jasl/Workspaces/Ruby/cybros && ruby test/acceptance/perf/workload_manifest_test.rb`
3. Implement minimal profile/topology/workload manifest classes.
4. Re-run the three tests until they pass.

**Requirements:**

- profile definitions must be code-owned, not ad-hoc scenario hashes
- topology must derive:
  - runtime label
  - runtime base URL
  - proxy port
  - home root
  - artifact root
  - event output path
  - container names
- each benchmark run must allocate a unique disposable root and keep runtime
  state isolated from prior runs
- no benchmark logic belongs in product apps

## Task 2: Extend acceptance runtime activation for multi-runtime orchestration

**Files:**

- Modify: `acceptance/bin/activate_agent_docker_runtime.sh`
- Modify: `acceptance/bin/fresh_start_stack.sh`
- Create: `acceptance/lib/perf/runtime_slot.rb`
- Create: `test/acceptance/perf/runtime_slot_test.rb`

**Steps:**

1. Write failing tests that assert each runtime slot gets unique:
   - port
   - container names
   - `FENIX_HOME_ROOT`
   - event output path
2. Run:
   - `cd /Users/jasl/Workspaces/Ruby/cybros && ruby test/acceptance/perf/runtime_slot_test.rb`
3. Implement runtime-slot derivation and teach the activation scripts to accept
   slot-specific env values.
4. Add support for `FENIX_RUNTIME_COUNT` as a validated orchestration input
   that later wrappers/scenarios can consume when expanding runtime slots.
5. Re-run the runtime-slot tests.

**Requirements:**

- multi-runtime boot must reuse the existing generic Docker activation path
- each runtime must remain isolated in local storage and ports
- each benchmark run must clean or recreate disposable home and artifact roots
- activation scripts must accept slot-specific container, volume, workspace,
  and perf-event env overrides
- stack boot must still support the single-runtime capstone path

## Task 3: Add benchmark-only event sinks to CoreMatrix and Fenix

**Files:**

- Create: `core_matrix/app/services/perf/event_sink.rb`
- Create: `core_matrix/config/initializers/perf_event_sink.rb`
- Create: `core_matrix/test/services/perf/event_sink_test.rb`
- Create: `agents/fenix/app/services/perf/event_sink.rb`
- Create: `agents/fenix/config/initializers/perf_event_sink.rb`
- Create: `agents/fenix/test/services/perf/event_sink_test.rb`

**Steps:**

1. Write failing tests in both apps that assert:
   - sink is inert when env vars are absent
   - sink appends one NDJSON line when enabled
   - sink preserves `*_public_id` fields / string identifiers only
2. Run the focused tests in each app.
3. Implement the minimal sink and initializer wiring.
4. Re-run the focused tests.

**Requirements:**

- env-gated only
- no benchmark DB writes
- one JSON object per line
- append-safe, low ceremony, no retries or queueing
- field names for product identifiers must use explicit `*_public_id` names

## Task 4: Add neutral CoreMatrix performance events

**Files:**

- Modify: `core_matrix/app/services/agent_control/poll.rb`
- Modify: `core_matrix/app/services/provider_execution/agent_request_exchange.rb`
- Modify one or more CoreMatrix queue-entry or queue-start boundaries that can
  emit enqueue-to-start timing
- Create: `core_matrix/app/services/perf/db_checkout_probe.rb`
- Create: `core_matrix/test/services/agent_control/poll_perf_test.rb`
- Create: `core_matrix/test/services/provider_execution/agent_request_exchange_perf_test.rb`
- Create: `core_matrix/test/services/perf/db_checkout_probe_test.rb`

**Steps:**

1. Write failing tests for:
   - poll completion event
   - mailbox lease latency event
   - mailbox exchange wait event
   - DB checkout probe event / timeout event
2. Run the focused CoreMatrix tests.
3. Implement minimal instrumentation.
4. Re-run focused tests.

**Requirements:**

- event names must be generic and benchmark-neutral
- use `*_public_id` fields in payloads
- DB checkout instrumentation must stay optional and benchmark-gated
- do not introduce durable telemetry writes for these high-frequency events

## Task 5: Add neutral Fenix runtime performance events

**Files:**

- Modify: `agents/fenix/app/services/runtime/control_plane.rb`
- Modify: `agents/fenix/app/services/runtime/mailbox_worker.rb`
- Modify any Fenix queue/job execution boundary required to measure start delay
- Create: `agents/fenix/app/services/perf/db_checkout_probe.rb`
- Create: `agents/fenix/test/services/runtime/control_plane_perf_test.rb`
- Create: `agents/fenix/test/services/runtime/mailbox_worker_perf_test.rb`
- Create: `agents/fenix/test/services/perf/db_checkout_probe_test.rb`

**Steps:**

1. Write failing tests for:
   - Fenix-side poll duration event
   - mailbox execution duration event
   - queue delay event if a clean boundary exists
   - DB checkout probe event / timeout event
2. Run the focused Fenix tests.
3. Implement the minimal instrumentation.
4. Re-run focused tests.

**Requirements:**

- event names must stay runtime-neutral and product-local
- no benchmark logic in runtime services
- runtime event payloads must identify the runtime instance label when enabled
- runtime event payloads must use `*_public_id` names for product identifiers

## Task 6: Build acceptance-side metric aggregation

**Files:**

- Create: `acceptance/lib/perf/event_reader.rb`
- Create: `acceptance/lib/perf/metrics_aggregator.rb`
- Create: `acceptance/lib/perf/report_builder.rb`
- Create: `test/acceptance/perf/metrics_aggregator_test.rb`
- Modify: `acceptance/lib/benchmark_reporting.rb`
- Modify: `acceptance/lib/artifact_bundle.rb`

**Steps:**

1. Write failing tests for:
   - event merge from multiple runtime files plus CoreMatrix file
   - `p50`/`p95`/`p99` calculations
   - per-runtime throughput
   - max queue pressure
   - DB checkout timeout counts
2. Run:
   - `cd /Users/jasl/Workspaces/Ruby/cybros && ruby test/acceptance/perf/metrics_aggregator_test.rb`
3. Implement minimal aggregation and report building.
4. Re-run the focused acceptance tests.

**Requirements:**

- aggregated metrics must be derived from benchmark artifact events, not live DB
  state after the fact
- summary must separate structural failure from capacity pressure
- no benchmark-specific language should leak into product apps

## Task 7: Add the multi-runtime load scenario

**Files:**

- Create: `acceptance/scenarios/multi_fenix_core_matrix_load_validation.rb`
- Create: `acceptance/lib/perf/workload_driver.rb`
- Create: `acceptance/lib/perf/runtime_registration_matrix.rb`
- Create: `test/acceptance/perf/workload_driver_test.rb`

**Steps:**

1. Write failing tests for:
   - one CoreMatrix plus N runtime registrations
   - round-robin conversation distribution
   - artifact paths per runtime
   - structural failure when a runtime does not boot
2. Run the focused acceptance tests.
3. Implement the minimal scenario driver.
4. Re-run the focused acceptance tests.

**Requirements:**

- default topology for v1 is multiple external agents, one per runtime
- `smoke` and `target_8_fenix` must use deterministic workload only
- deterministic v1 workload must stay narrow:
  - one conversation per scheduled workload slot
  - one mailbox turn in flight per conversation
  - fixed arithmetic or echo-style payload corpus only
  - no browser or workspace mutation work in the first benchmark profiles
- reuse the existing deterministic external mailbox/task path; do not invent a
  benchmark-only runtime execution mode
- scenario output must include:
  - runtime count
  - completed workload items
  - metric summaries
  - bottleneck hints

## Task 8: Add local execution wrappers for smoke and target profiles

**Files:**

- Create: `acceptance/bin/multi_fenix_core_matrix_load_smoke.sh`
- Create: `acceptance/bin/multi_fenix_core_matrix_load_target.sh`
- Modify: `acceptance/README.md`

**Steps:**

1. Add wrappers that:
   - boot the stack
   - select the benchmark profile
   - configure benchmark event output paths
   - invoke the new scenario
2. Document:
   - smoke profile
   - target 8-Fenix profile
   - expected artifact locations
3. Manually dry-run the shell scripts with `bash -n`.

**Requirements:**

- smoke wrapper must be small enough for routine developer use
- target wrapper must be explicit that it is a heavier local benchmark, not the
  default CI path

## Task 9: Verification and benchmark gate definition

**Files:**

- Modify: `acceptance/README.md`
- Modify any root CI or workflow config only if smoke benchmark is intentionally
  added to automation
- Create: `docs/plans/2026-04-09-multi-fenix-core-matrix-load-harness-follow-up.md` only if execution reveals follow-up threshold work

**Steps:**

1. Run focused tests for acceptance, CoreMatrix, and Fenix.
2. Run one local `smoke` benchmark and inspect the generated artifact bundle.
3. Run one local `target_8_fenix` benchmark and capture the first descriptive
   baseline numbers.
4. Record residual risks and threshold recommendations.

**Expected verification commands:**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
ruby test/acceptance/perf/profile_test.rb
ruby test/acceptance/perf/topology_test.rb
ruby test/acceptance/perf/workload_manifest_test.rb
ruby test/acceptance/perf/runtime_slot_test.rb
ruby test/acceptance/perf/metrics_aggregator_test.rb
ruby test/acceptance/perf/workload_driver_test.rb

cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rubocop -f github
bin/brakeman --no-pager
bin/bundler-audit
bun run lint:js
bin/rails db:test:prepare
bin/rails test

cd /Users/jasl/Workspaces/Ruby/cybros/agents/fenix
bin/rubocop -f github
bin/brakeman --no-pager
bin/bundler-audit
bin/rails db:test:prepare
bin/rails test

cd /Users/jasl/Workspaces/Ruby/cybros
bash -n acceptance/bin/multi_fenix_core_matrix_load_smoke.sh
bash -n acceptance/bin/multi_fenix_core_matrix_load_target.sh
```

**Definition of done for this plan:**

- a smoke benchmark can run end-to-end with multiple Fenix runtimes
- a target 8-Fenix benchmark can run locally and produce a complete artifact
  bundle
- the artifact bundle includes throughput, latency, queue pressure, mailbox
  pressure, and DB checkout pressure
- CoreMatrix and Fenix product code remain benchmark-neutral

## Notes For The Implementer

- Do not create a new top-level `benchmarks/` project in this phase.
- Do not put acceptance workload semantics into `core_matrix` or `agents/fenix`.
- Prefer deterministic workload first; provider-backed mixed load is a
  follow-up.
- Use public ids only in benchmark artifacts.
- Use explicit `*_public_id` field names for product identifiers in benchmark
  event payloads and summaries.
- Keep event sinks optional and low-perturbation.
