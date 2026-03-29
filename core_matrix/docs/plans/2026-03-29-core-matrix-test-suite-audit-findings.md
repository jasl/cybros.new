# Core Matrix Test Suite Audit Findings

## Batch 1

### Directory Summary

- `workflows`
  - Result: `keep_and_strengthen`
  - Notes: snapshot assembly and intent materialization tests protect real substrate invariants and benefitted from stronger payload and branch-path assertions.
- `turns`
  - Result: `keep_and_strengthen`
  - Notes: turn-entry and mutation-lock tests are behavior-focused. One refactor-residue alias assertion was removed.
- `conversations`
  - Result: `mixed, mostly keep_and_strengthen`
  - Notes: lifecycle tests carry real value, but several refactor-residue guard/alias assertions were removed because they only checked that deleted modules stayed deleted.
- `lineage_stores`
  - Result: `keep_and_strengthen`
  - Notes: compaction, set, delete, and garbage-collection tests all protect real lineage behavior. Compaction needed stronger assertions, not removal.
- `provider_execution`
  - Result: `keep_and_strengthen`
  - Notes: request context and persistence tests protect real contracts. Success and failure persistence now cover stale replay rejection explicitly.

### Low-Value Tests Removed In This Batch

- Removed legacy module/alias assertions from:
  - `test/services/conversations/archive_test.rb`
  - `test/services/conversations/purge_deleted_test.rb`
  - `test/services/conversations/finalize_deletion_test.rb`
  - `test/services/conversations/with_conversation_entry_lock_test.rb`
  - `test/services/conversations/validate_quiescence_test.rb`
  - `test/services/turns/with_timeline_mutation_lock_test.rb`
- Reason:
  - These assertions only encoded past refactor state and did not protect runtime behavior, invariants, or public contracts.

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

- Classification: `keep_and_strengthen`
- Protects:
  - archive requests require retained conversations
  - delete requests preserve archived lifecycle state while marking pending delete
- Closed In Current Batch:
  - intent-switch rejection while a close operation is unfinished
  - direct assertions on close-operation request timing semantics
  - same-intent retry idempotency
- Remaining:
  - queued-turn, active-turn, and background-resource side effects remain better covered elsewhere than here

### `test/services/lineage_stores/compact_snapshot_test.rb`

- Classification: `keep_and_strengthen`
- Protects:
  - compaction rewrites the visible key set into a depth-zero snapshot
- Closed In Current Batch:
  - lineage store continuity assertions
  - value reuse assertions for visible entries
  - stronger proof that tombstones are removed from the compacted snapshot, not just hidden in the query
- Remaining:
  - no direct stress case yet for multi-key chains with repeated overwrites before compaction

### `test/services/provider_execution/persist_turn_step_success_test.rb`

- Classification: `keep_and_strengthen`
- Protects:
  - terminal success writes selected output, usage, profiling, and status event side effects
- Closed In Current Batch:
  - output lineage assertions
  - usage evaluation metadata assertions
  - stale replay rejection under the shared execution lock
  - threshold-crossed true-branch coverage
- Remaining:
  - the higher-level integration path still checks usage rollups more than profiling payload details

### `test/services/provider_execution/persist_turn_step_failure_test.rb`

- Classification: `keep_and_strengthen`
- Protects:
  - terminal failure writes failed turn/workflow state and failure status events
- Closed In Current Batch:
  - stale replay rejection under the shared execution lock
- Remaining:
  - no direct coverage yet for alternative provider error classes beyond HTTP failures
