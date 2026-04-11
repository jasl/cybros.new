# Fenix and Nexus Deployment and Perf Refactor Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Split the default deployment topology into `CoreMatrix + Fenix + Nexus`, slim `Fenix` back to a normal Rails image, and update the acceptance perf harness to model shared `Fenix` and shared `Nexus` instances while collecting per-service telemetry.

**Architecture:** `Fenix` becomes a lightweight agent-plane service with a Rails-slim image and no dependency on the heavy Nexus base image. `Nexus` remains the heavy execution runtime image. The acceptance harness stops assuming one `Fenix` per runtime slot and instead models separate agent and runtime counts, with workload topology and reports carrying both dimensions. Perf reporting continues to use existing event sink telemetry, but summaries must break out `source_app` and instance labels so shared `Fenix` and shared `Nexus` deployments are visible.

**Tech Stack:** Ruby on Rails, Docker, shell acceptance harness, JSON perf artifacts.

---

### Task 1: Re-baseline Fenix container assumptions

**Files:**
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/Dockerfile`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/bin/check-runtime-host`
- Test: `/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/test/bin/check_runtime_host_test.rb`
- Reference: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/Dockerfile`

**Step 1: Write the failing tests**

Add coverage showing the Fenix host contract no longer requires Nexus-only dependencies such as Playwright, `pnpm`, or `uv`, but still checks the Rails/runtime essentials Fenix truly needs.

**Step 2: Run test to verify it fails**

Run: `cd /Users/jasl/Workspaces/Ruby/cybros/agents/fenix && bin/rails test test/bin/check_runtime_host_test.rb`

Expected: FAIL because the host-check implementation still requires heavy runtime dependencies.

**Step 3: Write minimal implementation**

Update the Fenix Dockerfile to start from a Rails-slim base instead of `NEXUS_BASE_IMAGE`, keeping only the packages Fenix actually needs. Reduce `bin/check-runtime-host` to the light agent-plane toolchain and remove browser/python/runtime bootstrap checks that belong to Nexus.

**Step 4: Run test to verify it passes**

Run: `cd /Users/jasl/Workspaces/Ruby/cybros/agents/fenix && bin/rails test test/bin/check_runtime_host_test.rb`

Expected: PASS.

**Step 5: Commit**

```bash
git add agents/fenix/Dockerfile agents/fenix/bin/check-runtime-host agents/fenix/test/bin/check_runtime_host_test.rb
git commit -m "refactor: slim fenix deployment contract"
```

### Task 2: Add the default top-level deployment topology

**Files:**
- Create: `/Users/jasl/Workspaces/Ruby/cybros/compose.yaml`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/acceptance/README.md`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/README.md`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/README.md`

**Step 1: Write the failing test or contract check**

Document the expected topology and, where practical, add a contract-level check that the compose file exposes `core_matrix`, `fenix`, and `nexus` services with distinct build contexts and shared wiring.

**Step 2: Run verification to verify it fails**

Run a focused schema/parse check such as:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
docker compose config >/tmp/cybros-compose.out
```

Expected: FAIL before the compose file exists or reflects the new topology.

**Step 3: Write minimal implementation**

Add a root `compose.yaml` that boots the three services with the right build contexts and environment contracts. Update docs so the default local stack and acceptance guidance point to the new split topology.

**Step 4: Run verification to verify it passes**

Run: `cd /Users/jasl/Workspaces/Ruby/cybros && docker compose config >/tmp/cybros-compose.out`

Expected: PASS with three resolved services.

**Step 5: Commit**

```bash
git add compose.yaml acceptance/README.md agents/fenix/README.md execution_runtimes/nexus/README.md
git commit -m "feat: add default corematrix fenix nexus compose stack"
```

### Task 3: Rework perf topology for shared agents and runtimes

**Files:**
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/acceptance/lib/perf/profile.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/acceptance/lib/perf/topology.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/acceptance/lib/perf/runtime_slot.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/acceptance/lib/perf/runtime_registration_matrix.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/acceptance/lib/perf/metrics_aggregator.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/acceptance/lib/perf/report_builder.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/acceptance/lib/perf/workload_driver.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/acceptance/lib/perf/workload_manifest.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/acceptance/scenarios/multi_fenix_core_matrix_load_validation.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/acceptance/bin/run_multi_fenix_core_matrix_load.sh`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/acceptance/README.md`
- Test: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/lib/acceptance/perf_workload_contract_test.rb`
- Test: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/lib/acceptance/perf_workload_executor_test.rb`
- Test: add or update harness unit tests around profile/topology/reporting if they already exist

**Step 1: Write the failing tests**

Add coverage for:
- separate `agent_count` and `execution_runtime_count`
- baseline `1 Fenix : 4 Nexus`
- shared runtime instance accounting in topology and reports
- per-`source_app` metrics breakdowns for `fenix`, `nexus`, and `core_matrix`

**Step 2: Run tests to verify they fail**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test test/lib/acceptance/perf_workload_contract_test.rb test/lib/acceptance/perf_workload_executor_test.rb
```

Expected: FAIL because the current perf code still models only `runtime_count` and “multi-fenix” slots.

**Step 3: Write minimal implementation**

Rename the perf topology away from “multi-fenix” semantics, introduce separate agent/runtime counts, and allow multiple runtime slots to share a single agent registration. Extend metrics aggregation and run summaries to group by `source_app` and `instance_label`, so the harness reports how shared Fenix and Nexus instances behaved.

**Step 4: Run tests to verify they pass**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test test/lib/acceptance/perf_workload_contract_test.rb test/lib/acceptance/perf_workload_executor_test.rb
```

Expected: PASS.

**Step 5: Commit**

```bash
git add acceptance/lib/perf acceptance/scenarios/multi_fenix_core_matrix_load_validation.rb acceptance/bin/run_multi_fenix_core_matrix_load.sh acceptance/README.md core_matrix/test/lib/acceptance
git commit -m "refactor: model shared fenix and nexus perf topology"
```

### Task 4: Run full verification and capture fresh baselines

**Files:**
- Update generated artifacts only if they are intended to be versioned
- Modify docs if fresh baseline numbers should replace stale values

**Step 1: Run project verification**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/agents/fenix && bin/brakeman --no-pager && bin/bundler-audit && bin/rubocop -f github && bin/rails db:test:prepare && bin/rails test
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && bin/brakeman --no-pager && bin/bundler-audit && bin/rubocop -f github && bun run lint:js && bin/rails db:test:prepare && bin/rails test && bin/rails test:system
cd /Users/jasl/Workspaces/Ruby/cybros
docker build -f images/nexus/Dockerfile -t nexus-local .
docker run --rm -v /Users/jasl/Workspaces/Ruby/cybros:/workspace nexus-local /workspace/images/nexus/verify.sh
```

Expected: PASS.

**Step 2: Run fresh perf baselines**

Run the smoke profile and the updated shared-runtime baseline profile, capture the artifact stamps, and extract the Fenix/Nexus/CoreMatrix metrics from the generated reports.

**Step 3: Update docs**

Refresh `acceptance/README.md` with the new benchmark names, topology counts, and baseline readings.

**Step 4: Commit**

```bash
git add acceptance/README.md docs/plans/2026-04-11-fenix-nexus-deployment-and-perf.md
git commit -m "docs: refresh split deployment perf baseline"
```
