# Core Matrix Test Suite Audit Findings

## Batch 1

### `test/services/workflows/build_execution_snapshot_test.rb`

- Classification: `keep_and_strengthen`
- Protects:
  - execution snapshot identity uses external `public_id` values
  - context projection excludes hidden transcript content
  - modality gating distinguishes runtime attachment visibility from model input eligibility
- Closed In Current Batch:
  - imported summary payload details
  - runtime attachment reference payload shape
  - superseded summary import filtering
  - direct source-message import lineage assertions
- Remaining:
  - modality coverage still leans on file and audio examples rather than the full multimodal matrix

### `test/services/workflows/intent_batch_materialization_test.rb`

- Classification: `keep_and_strengthen`
- Protects:
  - accepted intents materialize workflow-owned nodes
  - rejected intents stay audit-only
  - yield metadata is written back onto the workflow run
- Closed In Current Batch:
  - accepted node metadata payload assertions
  - manifest artifact count assertions
  - yield event linkage to barrier artifacts
  - multi-stage batches with selective barrier artifact creation
- Remaining:
  - no direct coverage yet for malformed batch manifests or missing resume successor payloads

### `test/services/turns/start_user_turn_test.rb`

- Classification: `keep_and_strengthen`
- Protects:
  - manual user turns bind to the conversation deployment
  - invalid addressability, lifecycle, and deletion states reject entry
- Closed In Current Batch:
  - explicit close-in-progress rejection
  - stronger input message lineage assertions on the created user message
- Remaining:
  - sequence-allocation behavior is still only indirectly covered

### `test/services/conversations/request_close_test.rb`

- Classification: `rewrite_or_lower`
- Protects:
  - archive requests require retained conversations
  - delete requests preserve archived lifecycle state while marking pending delete
- Closed In Current Batch:
  - intent-switch rejection while a close operation is unfinished
  - direct assertions on close-operation request timing semantics
- Remaining:
  - the file still adds limited value compared with broader lifecycle and purge tests
  - queued-turn, active-turn, and background-resource side effects remain better covered elsewhere than here

### `test/services/lineage_stores/compact_snapshot_test.rb`

- Classification: `rewrite_or_lower`
- Protects:
  - compaction rewrites the visible key set into a depth-zero snapshot
- Closed In Current Batch:
  - lineage store continuity assertions
  - value reuse assertions for visible entries
- Remaining:
  - stronger proof that tombstones are removed from the compacted snapshot, not just hidden in the query

### `test/services/provider_execution/persist_turn_step_success_test.rb`

- Classification: `keep_and_strengthen`
- Protects:
  - terminal success writes selected output, usage, profiling, and status event side effects
- Closed In Current Batch:
  - output lineage assertions
  - usage evaluation metadata assertions
  - stale replay rejection under the shared execution lock
- Remaining:
  - threshold-crossed behavior still only has false-branch coverage in this file
