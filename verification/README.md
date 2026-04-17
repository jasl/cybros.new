# Verification

`verification/` is the monorepo-owned validation project. It replaces the old
mixed harness surface and keeps cross-project harness code out of product
repositories.

`verification/Gemfile` is intentionally minimal. It supports the harness
itself, pure contracts, artifact/report builders, and shell helpers. It does
not inherit the `core_matrix` bundle.

## What Lives Here

- `bin/`: shell entrypoints for the active suite, fresh-start runs, load
  profiles, and proof wrappers
- `scenarios/e2e/`: automated end-to-end scenarios
- `scenarios/perf/`: load and topology validation scenarios
- `scenarios/proof/`: final proof entrypoints
- `lib/verification/support/`: harness-only helpers
- `lib/verification/suites/`: reusable e2e, perf, and proof code
- `test/`: harness-owned tests and contracts
- `artifacts/` and `logs/`: generated runtime output, intentionally untracked

## Canonical Commands

Run the pure harness-owned test lane:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
bash verification/bin/test_pure.sh
```

Run the CoreMatrix-hosted verification test lane:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
bash verification/bin/test_core_matrix_hosted.sh
```

Run both lanes:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
bash verification/bin/test_all.sh
```

Stop verification-managed daemons left behind by an interrupted run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
bash verification/bin/stop_managed_processes.sh
```

Run the active suite:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
bash verification/bin/run_active_suite.sh
```

Run the heavier optional `2048` proof together with the active suite:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
ACTIVE_VERIFICATION_ENABLE_2048_CAPSTONE=1 bash verification/bin/run_active_suite.sh
```

Run the capstone directly:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
bash verification/bin/fenix_capstone_app_api_roundtrip_validation.sh
```

Run one Ruby scenario through the `core_matrix` Rails environment:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails runner ../verification/scenarios/e2e/provider_backed_turn_validation.rb
```

## Active Surface

The active suite currently covers:

- operator setup:
  `verification/scenarios/e2e/core_matrix_cli_operator_smoke_validation.rb`
- deployment flows:
  `verification/scenarios/e2e/bring_your_own_agent_validation.rb`
  and `verification/scenarios/e2e/bring_your_own_execution_runtime_validation.rb`
- conversation and workflow control:
  `provider_backed_turn_validation.rb`,
  `specialist_subagent_export_validation.rb`,
  `workspace_agent_model_override_validation.rb`,
  `during_generation_steering_validation.rb`,
  `human_interaction_wait_resume_validation.rb`,
  `subagent_wait_all_validation.rb`,
  and `live_supervision_sidechat_validation.rb`
- governance and capability shaping:
  `governed_tool_validation.rb`,
  `governed_mcp_validation.rb`,
  and `fenix_skills_validation.rb`

The active suite manifest lives in
`verification/lib/verification/active_suite.rb`.

## Performance Harness

The Shared-Fenix / Multi-Nexus benchmark harness is owned here. Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
bash verification/bin/multi_fenix_core_matrix_load_smoke.sh
bash verification/bin/multi_fenix_core_matrix_load_target.sh
bash verification/bin/multi_fenix_core_matrix_load_stress.sh
```

The current benchmark shape is:

- one shared `Fenix` agent registration
- one or more `Nexus` execution-runtime registrations
- one or more concurrent conversations assigned per `Nexus` runtime
- aggregated perf evidence split by `source_app` and `instance_label`

Each run writes a bundle under `verification/artifacts/<artifact-stamp>/`,
including:

- `verification/artifacts/<artifact-stamp>/review/load-summary.md`
- `verification/artifacts/<artifact-stamp>/evidence/aggregated-metrics.json`
- `verification/artifacts/<artifact-stamp>/evidence/runtime-topology.json`
- `verification/artifacts/<artifact-stamp>/evidence/workload-profile.json`
- `verification/artifacts/<artifact-stamp>/evidence/run-summary.json`
- `verification/artifacts/<artifact-stamp>/evidence/core-matrix-events.ndjson`

## Proof Lane

The strongest final proof is:

- `verification/bin/fenix_capstone_app_api_roundtrip_validation.sh`

That proof is disabled by default in the active suite because it is a real
provider-backed end-to-end run. Enable it with
`ACTIVE_VERIFICATION_ENABLE_2048_CAPSTONE=1` when you explicitly want the full
gate.

## Ownership Rules

- product repositories keep product tests, including product-local e2e such as
  `core_matrix/test/e2e/protocol/*`
- `verification/` owns monorepo harness code, proof wrappers, perf harnesses,
  scenario entrypoints, and harness contracts
- scenario observation should prefer black-box surfaces such as `cmctl`,
  app API, logs, exports, and generated artifacts
- CoreMatrix-hosted verification is reserved for DB/internal-state inspection
  when there is no equivalent product surface yet
- generated review bundles, logs, exports, and perf evidence belong under
  `verification/artifacts/` and `verification/logs/`, not under `docs/`
- verification-managed daemon registries belong under `verification/tmp/` and
  can be cleared with `bash verification/bin/stop_managed_processes.sh`
