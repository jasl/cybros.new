# Acceptance Harness

Top-level acceptance automation lives here so `Core Matrix`, `Fenix`, and
`Nexus` stay
independent product codebases.

- `bin/` contains shell orchestrators for fresh-start and load runs.
- `scenarios/` contains Ruby acceptance scenarios.
- `lib/` contains harness-only support code.
- `artifacts/` and `logs/` are generated output directories and should stay out
  of git.

Run the canonical active acceptance suite:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
bash acceptance/bin/run_active_suite.sh
```

Run one active Ruby scenario through `Core Matrix`'s Rails environment:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
cd core_matrix
bin/rails runner ../acceptance/scenarios/<scenario>.rb
```

Current deployment-flow coverage includes:

- `acceptance/scenarios/bring_your_own_agent_validation.rb`
  - bring-your-own agent deployment using an externally registered Fenix agent
    plus external runtime
- `acceptance/scenarios/bring_your_own_execution_runtime_validation.rb`
  - bring-your-own execution runtime deployment for the bundled/default Fenix
    agent, including external runtime pairing and first task execution

Run the Shared-Fenix / Multi-Nexus load harness locally with the smoke profile:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
bash acceptance/bin/multi_fenix_core_matrix_load_smoke.sh
```

Run the heavier local target profile with one shared Fenix agent and four
host-side Nexus runtimes:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
bash acceptance/bin/multi_fenix_core_matrix_load_target.sh
```

Run the stress profile when validating provider-backed mailbox exchange pressure metrics:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
bash acceptance/bin/multi_fenix_core_matrix_load_stress.sh
```

Each load run writes an artifact bundle under
`acceptance/artifacts/<artifact-stamp>/` with the key outputs in:

- `acceptance/artifacts/<artifact-stamp>/review/load-summary.md`
- `acceptance/artifacts/<artifact-stamp>/evidence/aggregated-metrics.json`
- `acceptance/artifacts/<artifact-stamp>/evidence/runtime-topology.json`
- `acceptance/artifacts/<artifact-stamp>/evidence/workload-profile.json`
- `acceptance/artifacts/<artifact-stamp>/evidence/run-summary.json`
- `acceptance/artifacts/<artifact-stamp>/evidence/core-matrix-events.ndjson`

The current benchmark shape is:

- one shared `Fenix` agent registration
- one or more `Nexus` execution-runtime registrations
- one or more concurrent conversations assigned per `Nexus` runtime
- aggregated perf evidence split by `source_app` and `instance_label`, so
  `Fenix` and `Nexus` contributions can be inspected independently

Fresh local baselines, captured on April 11, 2026 after the shared-Fenix /
multi-Nexus perf refactor:

- `smoke` artifact `2026-04-11-171701-multi-agent-runtime-core-matrix-load-smoke`
  - `agent_count: 1`
  - `runtime_count: 2`
  - `completed_workload_items: 4`
  - `time_window.duration_seconds: 45.748`
  - `turn_latency.p95_ms: 1334.212`
  - `poll_latency.fenix_control_plane.p95_ms: 26.281`
  - `poll_latency.nexus_control_plane.p95_ms: 18.218`
- `baseline_1_fenix_4_nexus` artifact `2026-04-11-171756-multi-agent-runtime-core-matrix-load-baseline_1_fenix_4_nexus`
  - `agent_count: 1`
  - `runtime_count: 4`
  - `completed_workload_items: 8`
  - `time_window.duration_seconds: 66.377`
  - `turn_latency.p95_ms: 2388.374`
  - `poll_latency.fenix_control_plane.p95_ms: 71.173`
  - `poll_latency.nexus_control_plane.p95_ms: 71.173`
  - `queue_pressure.max_queue_delay_ms: 154.69`

Current benchmark gate recommendations:

- `smoke` is the fast correctness gate
  - require `structural_failures: []`
  - require `agent_count: 1`
  - require `runtime_count: 2`
  - require `completed_workload_items: 4`
  - require `review/load-summary.md`, `evidence/aggregated-metrics.json`, and `evidence/core-matrix-events.ndjson` to exist
- `baseline_1_fenix_4_nexus` is the queued runtime pressure gate
  - require non-zero `mailbox_lease_latency.count`
  - require non-zero `queue_pressure.total_sample_count`
  - require non-zero `database_checkout_pressure.checkout_wait.count`
  - require `database_checkout_pressure.timeout_count: 0`
  - inspect `throughput.per_source_app.fenix` and `throughput.per_source_app.nexus`
  - inspect `event_breakdown.fenix.instances` and `event_breakdown.nexus.instances`
  - investigate `queue_pressure.max_queue_delay_ms` regression against the latest local baseline
- `stress` is the provider-backed mailbox exchange pressure gate
  - require non-zero `mailbox_lease_latency.count`
  - require non-zero `mailbox_exchange_wait.count`
  - require non-zero `queue_pressure.total_sample_count`
  - require non-zero `database_checkout_pressure.checkout_wait.count`
  - require `database_checkout_pressure.timeout_count: 0`
  - investigate `queue_pressure.max_queue_delay_ms` and `mailbox_exchange_wait.p95_ms` regression against the latest local baseline

Current stabilization note:

- `smoke`, `baseline_1_fenix_4_nexus`, and `stress` are all local gates now
- `baseline_1_fenix_4_nexus` is the profile that validates one shared Fenix
  agent serving multiple host-side Nexus runtimes
- `stress` stays local-only for now; it is useful when touching provider/exchange scheduling, queue topology, or perf telemetry, but its latency numbers are still local descriptive baselines rather than hard CI thresholds
- `stress` currently drives the `role:mock` / `llm_dev` path, so it is a good local pressure gate for provider queueing and exchange behavior, but it is not a pure benchmark for OpenAI/OpenRouter HTTP transport changes by itself

`acceptance/Gemfile` reserves a dedicated top-level home for the harness, but
the supported execution path currently goes through `core_matrix/bin/rails`
so the acceptance scripts reuse the product Rails environment directly.
