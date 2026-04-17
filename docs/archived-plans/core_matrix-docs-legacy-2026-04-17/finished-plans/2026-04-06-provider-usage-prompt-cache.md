# Provider Usage Prompt Cache Metrics Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add durable prompt cache metrics to provider usage events, diagnostics, and debug export while preserving `available` vs `unknown` vs `unsupported` semantics.

**Architecture:** Extend the existing provider usage pipeline instead of the execution profiling pipeline. Normalize cache details once, persist them on `usage_events`, roll them into `usage_rollups`, and expose aggregate fields through diagnostics and debug export without adding any new runtime event protocol.

**Tech Stack:** Rails 8.2, PostgreSQL, Active Record, Minitest, vendored `simple_inference`

---

### Task 1: Add schema support for prompt cache telemetry

**Files:**
- Create: `db/migrate/20260406100000_add_prompt_cache_metrics_to_usage_telemetry.rb`
- Modify: `db/schema.rb`
- Test: `test/models/usage_event_test.rb`
- Test: `test/models/usage_rollup_test.rb`

**Step 1: Write failing model tests**

- Add assertions that `UsageEvent` accepts:
  - `prompt_cache_status = "available"` with `cached_input_tokens = 0`
  - `prompt_cache_status = "available"` with `cached_input_tokens = 12`
- Add assertions that `UsageEvent` rejects:
  - negative `cached_input_tokens`
  - `prompt_cache_status = "unknown"` with non-`nil` `cached_input_tokens`
  - `prompt_cache_status = "unsupported"` with non-`nil` `cached_input_tokens`

**Step 2: Run the targeted tests and confirm failure**

Run:

```bash
cd core_matrix
bin/rails test test/models/usage_event_test.rb test/models/usage_rollup_test.rb
```

Expected:

- failures for missing columns and missing validations

**Step 3: Add the migration**

- Add `prompt_cache_status` and `cached_input_tokens` to `usage_events`
- Add `cached_input_tokens_total`
- Add `prompt_cache_available_event_count`
- Add `prompt_cache_unknown_event_count`
- Add `prompt_cache_unsupported_event_count`
  to `usage_rollups`
- Add the same aggregate fields to:
  - `turn_diagnostics_snapshots`
  - `conversation_diagnostics_snapshots`

**Step 4: Update the schema-backed model validations**

- add enum or inclusion validation for `prompt_cache_status`
- add consistency validation between status and `cached_input_tokens`

**Step 5: Run the targeted tests again**

Run:

```bash
cd core_matrix
bin/rails db:test:prepare test test/models/usage_event_test.rb test/models/usage_rollup_test.rb
```

Expected:

- PASS

**Step 6: Commit**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
git add core_matrix/db/migrate/20260406100000_add_prompt_cache_metrics_to_usage_telemetry.rb core_matrix/db/schema.rb core_matrix/app/models/usage_event.rb core_matrix/test/models/usage_event_test.rb core_matrix/test/models/usage_rollup_test.rb
git commit -m "feat: add prompt cache usage telemetry schema"
```

### Task 2: Create one canonical provider usage normalizer

**Files:**
- Create: `app/services/provider_usage/normalize_metrics.rb`
- Modify: `app/services/provider_execution/dispatch_request.rb`
- Modify: `app/services/provider_execution/normalize_provider_response.rb`
- Modify: `app/services/provider_execution/persist_turn_step_success.rb`
- Modify: `app/services/provider_execution/persist_turn_step_yield.rb`
- Modify: `app/services/provider_gateway/dispatch_text.rb`
- Test: `test/services/provider_usage/normalize_metrics_test.rb`
- Test: `test/services/provider_execution/dispatch_request_test.rb`
- Test: `test/services/provider_execution/normalize_provider_response_test.rb`
- Test: `test/services/provider_gateway/dispatch_text_test.rb`

**Step 1: Write failing normalization tests**

- Add a unit test for chat-completions usage with:
  - `prompt_tokens`
  - `completion_tokens`
  - `total_tokens`
  - `prompt_tokens_details.cached_tokens`
- Add a unit test for usage with explicit `cached_tokens = 0`
- Add a unit test for usage with no cache detail returning `unknown`
- Add a unit test for explicit unsupported provider metadata returning `unsupported`

**Step 2: Run the new normalization test file**

Run:

```bash
cd core_matrix
bin/rails test test/services/provider_usage/normalize_metrics_test.rb
```

Expected:

- FAIL because the service does not exist yet

**Step 3: Implement `ProviderUsage::NormalizeMetrics`**

- input:
  - raw usage hash
  - optional provider capability metadata
- output:
  - `input_tokens`
  - `output_tokens`
  - `total_tokens`
  - `prompt_cache_status`
  - `cached_input_tokens`

**Step 4: Replace duplicated inline usage slicing**

- make the existing `normalize_usage` helpers delegate to the new service or
  remove them where possible
- keep all current token fields stable

**Step 5: Run the targeted service tests**

Run:

```bash
cd core_matrix
bin/rails test test/services/provider_usage/normalize_metrics_test.rb test/services/provider_execution/dispatch_request_test.rb test/services/provider_execution/normalize_provider_response_test.rb test/services/provider_gateway/dispatch_text_test.rb
```

Expected:

- PASS

**Step 6: Commit**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
git add core_matrix/app/services/provider_usage/normalize_metrics.rb core_matrix/app/services/provider_execution/dispatch_request.rb core_matrix/app/services/provider_execution/normalize_provider_response.rb core_matrix/app/services/provider_execution/persist_turn_step_success.rb core_matrix/app/services/provider_execution/persist_turn_step_yield.rb core_matrix/app/services/provider_gateway/dispatch_text.rb core_matrix/test/services/provider_usage/normalize_metrics_test.rb core_matrix/test/services/provider_execution/dispatch_request_test.rb core_matrix/test/services/provider_execution/normalize_provider_response_test.rb core_matrix/test/services/provider_gateway/dispatch_text_test.rb
git commit -m "feat: normalize prompt cache provider usage metrics"
```

### Task 3: Preserve cache metrics in vendored OpenAI-compatible helpers

**Files:**
- Modify: `vendor/simple_inference/lib/simple_inference/openai.rb`
- Modify: `vendor/simple_inference/lib/simple_inference/protocols/openai_compatible.rb`
- Modify: `vendor/simple_inference/lib/simple_inference/protocols/openai_responses.rb`
- Test: `vendor/simple_inference/test/test_openai_helpers.rb`
- Test: `vendor/simple_inference/test/test_openai_responses_protocol.rb`
- Test: `vendor/simple_inference/test/test_simple_inference_client.rb`

**Step 1: Write failing vendored helper tests**

- assert chat-completions usage preserves nested cache detail
- assert responses usage preserves nested cache detail
- assert streaming final usage preserves cache detail

**Step 2: Run the vendored tests**

Run:

```bash
cd core_matrix
ruby -Itest vendor/simple_inference/test/test_openai_helpers.rb
ruby -Itest vendor/simple_inference/test/test_openai_responses_protocol.rb
ruby -Itest vendor/simple_inference/test/test_simple_inference_client.rb
```

Expected:

- FAIL because current helpers only keep prompt/completion/total tokens

**Step 3: Update vendored usage extraction**

- keep existing token keys intact
- preserve nested cache detail so the CoreMatrix normalizer can inspect it
- do not break non-OpenAI-compatible fallback behavior

**Step 4: Re-run the vendored tests**

Run the same commands from Step 2.

Expected:

- PASS

**Step 5: Commit**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
git add core_matrix/vendor/simple_inference/lib/simple_inference/openai.rb core_matrix/vendor/simple_inference/lib/simple_inference/protocols/openai_compatible.rb core_matrix/vendor/simple_inference/lib/simple_inference/protocols/openai_responses.rb core_matrix/vendor/simple_inference/test/test_openai_helpers.rb core_matrix/vendor/simple_inference/test/test_openai_responses_protocol.rb core_matrix/vendor/simple_inference/test/test_simple_inference_client.rb
git commit -m "feat: preserve prompt cache usage details in simple inference"
```

### Task 4: Project prompt cache fields into usage events and rollups

**Files:**
- Modify: `app/services/provider_usage/record_event.rb`
- Modify: `app/services/provider_usage/project_rollups.rb`
- Modify: `app/queries/provider_usage/window_usage_query.rb`
- Test: `test/services/provider_usage/record_event_test.rb`
- Test: `test/services/provider_usage/project_rollups_test.rb`
- Test: `test/queries/provider_usage/window_usage_query_test.rb`
- Test: `test/integration/provider_usage_rollup_flow_test.rb`

**Step 1: Write failing projection tests**

- one test with `available` and non-zero cached tokens
- one test with `available` and zero cached tokens
- one test with `unknown`
- one test with `unsupported`

**Step 2: Run the provider usage tests**

Run:

```bash
cd core_matrix
bin/rails test test/services/provider_usage/record_event_test.rb test/services/provider_usage/project_rollups_test.rb test/queries/provider_usage/window_usage_query_test.rb test/integration/provider_usage_rollup_flow_test.rb
```

Expected:

- FAIL because the new fields are not being projected

**Step 3: Extend `RecordEvent`**

- accept `prompt_cache_status`
- accept `cached_input_tokens`
- persist them on the event row

**Step 4: Extend rollup projection**

- sum cached tokens only for `available` rows
- increment the status-specific counters correctly

**Step 5: Re-run the provider usage tests**

Run the same command from Step 2.

Expected:

- PASS

**Step 6: Commit**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
git add core_matrix/app/services/provider_usage/record_event.rb core_matrix/app/services/provider_usage/project_rollups.rb core_matrix/app/queries/provider_usage/window_usage_query.rb core_matrix/test/services/provider_usage/record_event_test.rb core_matrix/test/services/provider_usage/project_rollups_test.rb core_matrix/test/queries/provider_usage/window_usage_query_test.rb core_matrix/test/integration/provider_usage_rollup_flow_test.rb
git commit -m "feat: project prompt cache metrics through usage rollups"
```

### Task 5: Extend diagnostics aggregation with prompt cache metrics

**Files:**
- Modify: `app/services/conversation_diagnostics/recompute_turn_snapshot.rb`
- Modify: `app/services/conversation_diagnostics/recompute_conversation_snapshot.rb`
- Modify: `app/controllers/app_api/conversation_diagnostics_controller.rb`
- Test: `test/services/conversation_diagnostics/recompute_turn_snapshot_test.rb`
- Test: `test/services/conversation_diagnostics/recompute_conversation_snapshot_test.rb`
- Test: `test/requests/app_api/conversation_diagnostics_test.rb`

**Step 1: Write failing diagnostics tests**

- turn diagnostics should return:
  - `cached_input_tokens_total`
  - `prompt_cache_available_event_count`
  - `prompt_cache_unknown_event_count`
  - `prompt_cache_unsupported_event_count`
  - `prompt_cache_hit_rate`
- `prompt_cache_hit_rate` must be `null` when there are no `available` events

**Step 2: Run the diagnostics tests**

Run:

```bash
cd core_matrix
bin/rails test test/services/conversation_diagnostics/recompute_turn_snapshot_test.rb test/services/conversation_diagnostics/recompute_conversation_snapshot_test.rb test/requests/app_api/conversation_diagnostics_test.rb
```

Expected:

- FAIL because the fields are absent

**Step 3: Extend snapshot recompute logic**

- aggregate cached tokens only from `available` rows
- aggregate the three status counters
- derive hit rate from `available` rows only

**Step 4: Extend API serialization**

- add the new aggregate fields to conversation and turn diagnostics responses
- keep `prompt_cache_hit_rate` nullable

**Step 5: Re-run the diagnostics tests**

Run the same command from Step 2.

Expected:

- PASS

**Step 6: Commit**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
git add core_matrix/app/services/conversation_diagnostics/recompute_turn_snapshot.rb core_matrix/app/services/conversation_diagnostics/recompute_conversation_snapshot.rb core_matrix/app/controllers/app_api/conversation_diagnostics_controller.rb core_matrix/test/services/conversation_diagnostics/recompute_turn_snapshot_test.rb core_matrix/test/services/conversation_diagnostics/recompute_conversation_snapshot_test.rb core_matrix/test/requests/app_api/conversation_diagnostics_test.rb
git commit -m "feat: expose prompt cache metrics in diagnostics"
```

### Task 6: Extend debug export with raw and aggregate prompt cache fields

**Files:**
- Modify: `app/services/conversation_debug_exports/build_payload.rb`
- Test: `test/services/conversation_debug_exports/build_payload_test.rb`

**Step 1: Write failing debug export tests**

- raw exported `usage_events` should include:
  - `prompt_cache_status`
  - `cached_input_tokens`
- exported diagnostics snapshots should include aggregate prompt cache fields

**Step 2: Run the debug export test**

Run:

```bash
cd core_matrix
bin/rails test test/services/conversation_debug_exports/build_payload_test.rb
```

Expected:

- FAIL because the export omits the new fields

**Step 3: Implement export serialization**

- add raw event fields to exported `usage_events`
- add aggregate fields to exported turn/conversation diagnostics snapshots

**Step 4: Re-run the debug export test**

Run the same command from Step 2.

Expected:

- PASS

**Step 5: Commit**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
git add core_matrix/app/services/conversation_debug_exports/build_payload.rb core_matrix/test/services/conversation_debug_exports/build_payload_test.rb
git commit -m "feat: include prompt cache metrics in debug export"
```

### Task 7: Document the new provider usage contract

**Files:**
- Modify: `docs/behavior/provider-usage-events-and-rollups.md`
- Modify: `docs/behavior/execution-profiling-facts.md`

**Step 1: Update provider usage behavior docs**

- document `prompt_cache_status`
- document `cached_input_tokens`
- document aggregate hit-rate semantics
- document that `unknown` is excluded from the denominator

**Step 2: Update profiling docs**

- explicitly state prompt cache metrics remain outside `execution_profile_facts`

**Step 3: Commit**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
git add core_matrix/docs/behavior/provider-usage-events-and-rollups.md core_matrix/docs/behavior/execution-profiling-facts.md
git commit -m "docs: describe prompt cache usage telemetry"
```

### Task 8: Run focused verification, then full project verification

**Files:**
- Inspect: `tmp/test.log`

**Step 1: Run the focused suite**

Run:

```bash
cd core_matrix
bin/rails db:test:prepare test \
  test/models/usage_event_test.rb \
  test/models/usage_rollup_test.rb \
  test/services/provider_usage/normalize_metrics_test.rb \
  test/services/provider_usage/record_event_test.rb \
  test/services/provider_usage/project_rollups_test.rb \
  test/queries/provider_usage/window_usage_query_test.rb \
  test/services/conversation_diagnostics/recompute_turn_snapshot_test.rb \
  test/services/conversation_diagnostics/recompute_conversation_snapshot_test.rb \
  test/requests/app_api/conversation_diagnostics_test.rb \
  test/services/conversation_debug_exports/build_payload_test.rb \
  test/integration/provider_usage_rollup_flow_test.rb
```

Expected:

- PASS

**Step 2: Run vendored helper verification**

Run:

```bash
cd core_matrix
ruby -Itest vendor/simple_inference/test/test_openai_helpers.rb
ruby -Itest vendor/simple_inference/test/test_openai_responses_protocol.rb
ruby -Itest vendor/simple_inference/test/test_simple_inference_client.rb
```

Expected:

- PASS

**Step 3: Run full project verification**

Run:

```bash
cd core_matrix
bin/brakeman --no-pager
bin/bundler-audit
bin/rubocop -f github
bun run lint:js
bin/rails db:test:prepare test
bin/rails db:test:prepare test:system
```

Expected:

- PASS

**Step 4: Final commit**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
git status --short
git add core_matrix
git commit -m "feat: add prompt cache metrics to provider usage diagnostics"
```
