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

The `2048 capstone` is part of the formal acceptance surface but is disabled by
default because it is a heavy, real provider-backed final proof. Enable it
inside the active suite only when you explicitly want that proof to run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
ACTIVE_ACCEPTANCE_ENABLE_2048_CAPSTONE=1 bash acceptance/bin/run_active_suite.sh
```

Run the capstone directly when you want the strongest end-to-end proof without
running the rest of the suite:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
bash acceptance/bin/fenix_capstone_app_api_roundtrip_validation.sh
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

Current acceptance matrix, organized by purpose:

- Operator setup
  - `acceptance/scenarios/core_matrix_cli_operator_smoke_validation.rb`
    - validates the black-box `cmctl` bootstrap/auth/provider/workspace/mount flow
      against the real local stack
- Deployment flows
  - `acceptance/scenarios/bring_your_own_agent_validation.rb`
    - validates the `BYO agent + BYO runtime` onboarding path
  - `acceptance/scenarios/bring_your_own_execution_runtime_validation.rb`
    - validates the `bundled Fenix + BYO runtime` onboarding path
- Conversation/workflow control
  - `acceptance/scenarios/provider_backed_turn_validation.rb`
    - proves a real provider-backed turn can complete end-to-end
  - `acceptance/scenarios/specialist_subagent_export_validation.rb`
    - proves `tester` specialist delegation is visible in ordinary export,
      debug export, and `review/workflow-mermaid.md`
  - `acceptance/scenarios/workspace_agent_model_override_validation.rb`
    - proves mounted `WorkspaceAgent.settings_payload` can override the
      interactive model selector for an app-api conversation without an explicit
      selector on create
  - `acceptance/scenarios/during_generation_steering_validation.rb`
    - validates reject / restart / queue behavior while active work exists
  - `acceptance/scenarios/human_interaction_wait_resume_validation.rb`
    - validates human wait-state creation and resume behavior
  - `acceptance/scenarios/subagent_wait_all_validation.rb`
    - validates subagent barrier coordination and successor release
- Governance and capability shaping
  - `acceptance/scenarios/governed_tool_validation.rb`
    - validates reserved tool governance and governed tool invocation wiring
  - `acceptance/scenarios/governed_mcp_validation.rb`
    - validates governed MCP transport behavior and session recovery
  - `acceptance/scenarios/fenix_skills_validation.rb`
    - validates portable skill activation, sharing, and isolation boundaries
- Performance and topology pressure
  - `acceptance/scenarios/multi_fenix_core_matrix_load_validation.rb`
    - canonical load scenario used by the `smoke`, `target`, and `stress`
      shell wrappers; this is not an orphaned scenario even though it is
      normally entered through `acceptance/bin/run_multi_fenix_core_matrix_load.sh`
- Final proof
  - `acceptance/bin/fenix_capstone_app_api_roundtrip_validation.sh`
    - real provider-backed `2048 capstone` proof over the current `Fenix + Nexus`
      split topology
    - kept as the strongest final acceptance standard and disabled by default in
      `run_active_suite.sh`

Current final-proof coverage includes:

- `acceptance/bin/fenix_capstone_app_api_roundtrip_validation.sh`
  - real provider-backed `2048 capstone` proof over the current `Fenix + Nexus`
    split topology
  - disabled by default in `run_active_suite.sh`

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
