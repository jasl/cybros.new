# Core Matrix Test Suite Audit Findings

## Batch 1

### `test/services/workflows/build_execution_snapshot_test.rb`

- Classification: `keep_and_strengthen`
- Protects:
  - execution snapshot identity uses external `public_id` values
  - context projection excludes hidden transcript content
  - modality gating distinguishes runtime attachment visibility from model input eligibility
- Missing:
  - imported summary payload details
  - runtime attachment reference payload shape
  - more explicit import source lineage assertions

### `test/services/workflows/intent_batch_materialization_test.rb`

- Classification: `keep_and_strengthen`
- Protects:
  - accepted intents materialize workflow-owned nodes
  - rejected intents stay audit-only
  - yield metadata is written back onto the workflow run
- Missing:
  - accepted node metadata payload assertions
  - manifest artifact count assertions
  - yield event linkage to barrier artifacts

### `test/services/turns/start_user_turn_test.rb`

- Classification: `keep_and_strengthen`
- Protects:
  - manual user turns bind to the conversation deployment
  - invalid addressability, lifecycle, and deletion states reject entry
- Missing:
  - explicit close-in-progress rejection
  - stronger input message lineage assertions on the created user message

### `test/services/conversations/request_close_test.rb`

- Classification: `rewrite_or_lower`
- Protects:
  - archive requests require retained conversations
  - delete requests preserve archived lifecycle state while marking pending delete
- Missing:
  - intent-switch rejection while a close operation is unfinished
  - direct assertions on close-operation request semantics
  - evidence that the wrapper adds value beyond neighboring lifecycle tests

### `test/services/lineage_stores/compact_snapshot_test.rb`

- Classification: `rewrite_or_lower`
- Protects:
  - compaction rewrites the visible key set into a depth-zero snapshot
- Missing:
  - lineage store continuity assertions
  - value reuse assertions for visible entries
  - stronger proof that tombstones are removed from the compacted snapshot, not just hidden in the query

### `test/services/provider_execution/persist_turn_step_success_test.rb`

- Classification: `keep_and_strengthen`
- Protects:
  - terminal success writes selected output, usage, profiling, and status event side effects
- Missing:
  - output lineage assertions
  - usage evaluation metadata assertions
  - stale replay rejection under the shared execution lock
