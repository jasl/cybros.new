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
  - follow-up overflow tests now cover repeated overwrite and delete chains through `set` and `delete_key`; remaining gaps are scale-oriented, not continuity-oriented

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

## Batch 2

### Directory Summary

- `agent_control`
  - Result: `keep_and_strengthen`
  - Notes: mailbox publication, delivery, and polling tests already protect lease semantics and public envelopes. No refactor-residue cleanup was needed here.
- `agent_deployments`
  - Result: `keep_and_strengthen`
  - Notes: bootstrap, registration, handshake, and recovery tests all encode real deployment lifecycle behavior. Bootstrap specifically needed a stronger failure-path assertion.
- `subagent_connections`
  - Result: `keep_and_strengthen`
  - Notes: spawn and listing tests protect ownership scoping, nested depth, and public-id-only boundaries. The legacy naming rejection remains valuable because it guards an agent-facing input contract, not an internal alias.
- `installations`
  - Result: `keep_and_strengthen`
  - Notes: bundled-runtime registration and bootstrap tests protect idempotent reconciliation and deployment selection. Registration now covers supersession behavior explicitly.
- `execution_environments`
  - Result: `keep`
  - Notes: environment reconciliation and capability recording tests are already behavior-oriented and did not warrant cleanup in this pass.

### Low-Value Tests Removed In This Batch

- None.
- Reason:
  - The surviving Batch 2 "legacy" checks were reviewed and kept only where they still protect current external contracts.

### `test/services/agent_deployments/bootstrap_test.rb`

- Classification: `keep_and_strengthen`
- Protects:
  - deployment bootstrap creates a system-owned automation conversation, turn, workflow, and audit trail
- Closed In Current Batch:
  - mismatched workspace and deployment installation rejection
  - proof that the installation guard fails before any write-side side effects occur
- Remaining:
  - bootstrap idempotency keys remain intentionally unasserted because they are implementation detail, not product contract

### `test/services/installations/register_bundled_agent_runtime_test.rb`

- Classification: `keep_and_strengthen`
- Protects:
  - bundled runtime registration reconciles agent installation, execution environment, deployment, and capability snapshot without duplicate rows
- Closed In Current Batch:
  - fingerprint-change supersession of the previous active deployment
  - endpoint and environment connection metadata refresh
  - connection credential digest rotation for the new bundled fingerprint
- Remaining:
  - no multi-revision stress case yet for large profile and tool catalog diffs across successive bundled runtime updates

## Batch 3

### Directory Summary

- `queries`
  - Result: `mixed, mostly keep_and_strengthen`
  - Notes: blocker snapshots, key listing, and provider usage tests all protect real read-side behavior. One blocker snapshot test carried refactor-residue constant checks that were removed.
- `projections`
  - Result: `keep_and_strengthen`
  - Notes: workflow, publication, and transcript projection tests protect ordering, visibility, and pagination. Refactor-residue owner/query assertions were removed.
- `resolvers`
  - Result: `keep_and_strengthen`
  - Notes: visible-values resolution protects the merged read contract; the legacy resolver alias check was removed.
- `agent_api` controllers and requests
  - Result: `keep_and_strengthen`
  - Notes: request tests protect external public-id contracts, handshake payload shape, and machine-facing health responses. Registration and health checks benefitted from stronger default-path assertions.

### Low-Value Tests Removed In This Batch

- Removed refactor-residue owner/query assertions from:
  - `test/projections/workflows/projection_test.rb`
  - `test/projections/publications/live_projection_test.rb`
  - `test/projections/conversation_transcripts/page_projection_test.rb`
  - `test/resolvers/conversation_variables/visible_values_resolver_test.rb`
- Removed refactor-residue constant checks from:
  - `test/queries/conversations/blocker_snapshot_query_test.rb`
- Reason:
  - These checks only recorded the absence of deleted query owners and did not add behavioral protection for the current read path.

### `test/queries/lineage_stores/list_keys_query_test.rb`

- Classification: `keep_and_strengthen`
- Protects:
  - visible lineage keys page in stable key order without loading value payload rows
- Closed In Current Batch:
  - exclusive cursor semantics
  - zero and invalid limit clamping behavior
- Remaining:
  - no direct coverage yet for very deep snapshot chains with hundreds of keys

### `test/queries/provider_usage/window_usage_query_test.rb`

- Classification: `keep_and_strengthen`
- Protects:
  - rolling-window usage aggregation across provider, model, and operation dimensions
- Closed In Current Batch:
  - explicit `window_key` contract on returned entries
  - empty-window behavior
- Remaining:
  - no direct read-side assertion yet for mixed media usage rows beyond token-centric cases

### `test/requests/agent_api/registrations_test.rb`

- Classification: `keep_and_strengthen`
- Protects:
  - registration exchanges enrollment tokens for a public-id deployment contract and separated capability snapshot
- Closed In Current Batch:
  - default environment kind fallback
  - endpoint metadata fallback into execution environment connection metadata
  - empty environment capability payload default path
  - malformed environment capability payload rejection
  - malformed profile/config/default contract rejection
- Remaining:
  - low-risk passive endpoints still rely on shared base-controller behavior more than endpoint-specific negative tests

### `test/requests/agent_api/capabilities_test.rb`

- Classification: `keep_and_strengthen`
- Protects:
  - capability refresh and handshake return the machine-facing runtime contract without leaking internal identifiers
- Closed In Follow-Up:
  - malformed environment capability payload rejection
  - malformed profile/config/default contract rejection
  - handshake failure path preserves the previously active capability snapshot version
- Remaining:
  - no dedicated request-level stress case yet for very large tool catalogs or profile catalogs

### `test/requests/agent_api/health_test.rb`

- Classification: `keep_and_strengthen`
- Protects:
  - machine-facing health endpoint returns deployment identity and liveness state without leaking internal ids
- Closed In Current Batch:
  - bootstrap state, protocol version, sdk version, and heartbeat timestamp response shape
- Remaining:
  - no explicit offline or degraded health response case yet

## Second-Pass Hardening

### `RuntimeCapabilityContract` and `AgentDeployments::ReconcileConfig`

- Classification: `strengthened`
- Protects:
  - invalid non-hash runtime contract payloads now survive long enough to reach Active Record validation and produce `422` responses instead of transport-layer `500`s
  - selector reconciliation no longer assumes the incoming schema snapshot is hash-shaped
- Closed In Follow-Up:
  - malformed request payloads for `registrations` and `capabilities` now fail as business errors
- Remaining:
  - empty arrays are still normalized as blank payloads by design; future tightening should only happen if the API contract explicitly forbids that coercion

### `test/services/lineage_stores/set_test.rb` and `test/services/lineage_stores/delete_key_test.rb`

- Classification: `keep_and_strengthen`
- Protects:
  - depth-32 rollover compacts before continuing the write chain
  - latest surviving values remain visible after repeated overwrites and delete-driven compaction
- Closed In Follow-Up:
  - repeated overwrite continuity across compaction
  - delete-path compaction continuity and tombstone placement
- Remaining:
  - no broad performance-oriented sweep yet for very wide keyspaces

### `test/services/agent_control/handle_execution_report_test.rb` and `test/services/agent_control/handle_close_report_test.rb`

- Classification: `keep_and_strengthen`
- Protects:
  - stale heartbeat timeouts are translated into `stale` execution reports without mutating progress state
  - expired close-request mailbox leases are translated into `stale` close reports without mutating durable close state
- Closed In Follow-Up:
  - wrapper-level stale translation coverage that previously relied only on higher-level `report` and request tests
- Remaining:
  - `lease_mailbox_item` and `progress_close_request` still rely primarily on higher-level delivery/escalation coverage
