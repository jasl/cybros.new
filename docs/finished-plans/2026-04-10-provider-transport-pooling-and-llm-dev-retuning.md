# Provider Transport Pooling and llm_dev Retuning Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Reduce provider-backed overhead and queue delay by switching real provider traffic to pooled HTTPX and raising the `llm_dev` baseline for the verified `8 Fenix` host target.

**Architecture:** Keep the existing `SimpleInference` abstraction and provider contracts. First move real providers onto the vendored persistent HTTPX adapter, then re-tune `llm_dev` concurrency using focused config tests and acceptance perf evidence.

**Tech Stack:** Ruby on Rails, Solid Queue, SimpleInference, HTTPX, acceptance/perf harness

---

### Task 1: Route real providers through pooled HTTPX

**Files:**
- Modify: `core_matrix/app/services/provider_execution/build_http_adapter.rb`
- Test: `core_matrix/test/services/provider_execution/build_http_adapter_test.rb`
- Test: `core_matrix/test/services/provider_execution/dispatch_request_test.rb`
- Test: `core_matrix/test/services/provider_gateway/dispatch_text_test.rb`

**Steps:**
1. Write failing tests asserting real provider adapter keys build `SimpleInference::HTTPAdapters::HTTPX` while mock keys remain on `Default`.
2. Run the focused adapter/provider tests to verify the old mapping still fails the new expectation.
3. Implement the minimal adapter-key remap.
4. Re-run the focused tests and then the relevant full `core_matrix` verification.

### Task 2: Re-tune the llm_dev baseline

**Files:**
- Modify: `core_matrix/config/runtime_topology.yml`
- Modify: `core_matrix/config/queue.yml`
- Modify: `core_matrix/config/database.yml`
- Modify: `core_matrix/env.sample`
- Test: `core_matrix/test/config/queue_configuration_test.rb`
- Test: `core_matrix/test/config/performance_baseline_test.rb`
- Test: `core_matrix/test/lib/acceptance/perf_workload_contract_test.rb`

**Steps:**
1. Write failing config/perf tests for the widened `llm_dev` baseline and any required pool adjustments.
2. Run the focused tests to confirm the current topology stays below the new baseline.
3. Implement the queue/database/env changes with the smallest viable widening.
4. Re-run focused tests and then full `core_matrix` verification.

### Task 3: Re-baseline perf and docs

**Files:**
- Modify: `acceptance/README.md`
- Modify: `docs/future-plans/2026-04-09-multi-fenix-core-matrix-load-harness-follow-up.md`
- Modify/add acceptance perf tests if expectations need tightening under `test/acceptance/perf`

**Steps:**
1. Re-run `smoke`, `target_8_fenix`, and `stress` after the transport and queue changes are real.
2. Compare throughput, queue delay, and turn latency against the April 10 baseline.
3. Update docs only with verified new baselines and remaining follow-up work.

### Task 4: Final review and verification

**Files:**
- Review all touched files

**Steps:**
1. Run a strict self-review across the whole diff.
2. Fix findings before claiming completion.
3. Run full repository verification:
   - `agents/fenix` verification commands from `AGENTS.md`
   - `core_matrix` verification commands from `AGENTS.md`
   - `core_matrix/vendor/simple_inference` verification from `AGENTS.md`
   - Docker verify for `images/nexus`
   - acceptance perf scripts
4. Only then commit.
