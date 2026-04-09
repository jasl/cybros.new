# Acceptance Harness

Top-level acceptance automation lives here so `Core Matrix` and `Fenix` stay
independent product codebases.

- `bin/` contains shell orchestrators for fresh-start and capstone runs.
- `scenarios/` contains Ruby acceptance scenarios.
- `lib/` contains harness-only support code.
- `artifacts/` and `logs/` are generated output directories and should stay out
  of git.

The 2048 capstone now writes an organized artifact bundle per run:

- `review/` for human-readable transcripts, supervision views, and validation notes
- `evidence/` for machine-readable benchmark outputs and diagnostics
- `logs/` for timeline and supervision logs
- `exports/` for export/debug-export/import roundtrip bundles and metadata
- `playable/` for host-side build, preview, and browser-verification outputs
- `tmp/` for unpacked debug bundles and scratch files

Each bundle includes:

- `review/index.md` as the human-readable entry point
- `evidence/artifact-manifest.json` as the canonical machine-readable entry point

Run acceptance scenarios through `Core Matrix`'s Rails environment:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
cd core_matrix
bin/rails runner ../acceptance/scenarios/<scenario>.rb
```

Run the 2048 capstone with a fresh stack:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
bash acceptance/bin/fenix_capstone_app_api_roundtrip_validation.sh
```

That wrapper rebuilds `images/nexus`, rebuilds the `agents/fenix` app image on
top of it, performs bootstrap registration, and then activates the Dockerized
runtime through the generic `acceptance/bin/activate_agent_docker_runtime.sh`
entrypoint via the thin Fenix-specific wrapper.

Run the multi-Fenix load harness locally with the smoke profile:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
bash acceptance/bin/multi_fenix_core_matrix_load_smoke.sh
```

Run the heavier local target profile with eight host-side Fenix runtimes:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
bash acceptance/bin/multi_fenix_core_matrix_load_target.sh
```

Run the stress profile when validating the real queue plane and pressure metrics:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
bash acceptance/bin/multi_fenix_core_matrix_load_stress.sh
```

Each load run writes an artifact bundle under `acceptance/artifacts/<artifact-stamp>/`
with the key outputs in:

- `acceptance/artifacts/<artifact-stamp>/review/load-summary.md`
- `acceptance/artifacts/<artifact-stamp>/evidence/aggregated-metrics.json`
- `acceptance/artifacts/<artifact-stamp>/evidence/runtime-topology.json`
- `acceptance/artifacts/<artifact-stamp>/evidence/workload-profile.json`
- `acceptance/artifacts/<artifact-stamp>/evidence/run-summary.json`
- `acceptance/artifacts/<artifact-stamp>/evidence/core-matrix-events.ndjson`

Current local benchmark baselines, captured on April 9, 2026:

- `smoke` artifact `2026-04-09-task8-wrapper-smoke-v3`
  - `runtime_count: 2`
  - `completed_workload_items: 4`
  - `time_window.duration_seconds: 9.01`
  - `turn_latency.p95_ms: 2020.631`
  - `poll_latency.core_matrix_control_plane.p95_ms: 10.972`
- `target_8_fenix` artifact `2026-04-09-task9-target-8-fenix-v1`
  - `runtime_count: 8`
  - `completed_workload_items: 16`
  - `time_window.duration_seconds: 33.018`
  - `throughput.completed_workload_items_per_minute: 29.075`
  - `turn_latency.p95_ms: 6761.269`
  - `poll_latency.fenix_control_plane.p95_ms: 149.401`
  - `poll_latency.core_matrix_control_plane.p95_ms: 5.614`

Current benchmark gate recommendations:

- `smoke` is the candidate correctness gate
  - require `structural_failures: []`
  - require `runtime_count: 2`
  - require `completed_workload_items: 4`
  - require `review/load-summary.md`, `evidence/aggregated-metrics.json`, and `evidence/core-matrix-events.ndjson` to exist
- `target_8_fenix` remains a local descriptive benchmark, not a CI default
  - investigate if `completed_workload_items < 16`
  - investigate if `turn_latency.p95_ms > 10000`
  - investigate if `poll_latency.fenix_control_plane.p95_ms > 300`
  - investigate if `poll_latency.core_matrix_control_plane.p99_ms > 50`
  - investigate any non-zero `database_checkout_pressure.timeout_count`
- `stress` is the queue-plane pressure profile
  - require non-zero `mailbox_lease_latency.count`
  - require non-zero `mailbox_exchange_wait.count`
  - require non-zero `queue_pressure.total_sample_count`
  - require non-zero `database_checkout_pressure.checkout_wait.count`
  - require `database_checkout_pressure.timeout_count: 0`
  - investigate any `gate.outcome: failed`

Current stabilization note:

- `smoke` and `target_8_fenix` are the stable local reference profiles
- `stress` now routes through the real queue plane and emits pressure metrics,
  but it should still be treated as an active stabilization profile until the
  local jobs daemon startup path proves consistently healthy across fresh-start
  runs

Replay the supervision review surfaces from an existing evaluation bundle:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
bash acceptance/bin/replay_supervision_eval.sh /absolute/path/to/review/supervision-eval-bundle.json
```

`acceptance/Gemfile` reserves a dedicated top-level home for the harness, but
the supported execution path currently goes through `core_matrix/bin/rails`
so the acceptance scripts reuse the product Rails environment directly.
