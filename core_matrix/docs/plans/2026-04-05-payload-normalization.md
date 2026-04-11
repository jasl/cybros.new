# Payload Normalization Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace duplicated inline execution and audit JSON with normalized execution contracts, snapshots, and immutable JSON documents.

**Architecture:** Introduce `JsonDocument`, `ExecutionCapabilitySnapshot`, `ExecutionContextSnapshot`, and `ExecutionContract`; keep runtime-facing request/response shapes mostly stable by materializing them from normalized rows at read time. Hot operational tables keep refs and compact facts, while large JSON bodies move to document refs.

**Tech Stack:** Rails 8.2, PostgreSQL JSONB, Active Record, Minitest

---

### Task 1: Add the new schema primitives

**Files:**
- Modify: `db/migrate/20260324090021_create_turns.rb`
- Modify: `db/migrate/20260326113000_add_agent_control_contract.rb`
- Modify: `db/migrate/20260324090032_create_workflow_artifacts.rb`
- Modify: `db/migrate/20260324090025_create_tool_invocations.rb`
- Modify: `db/migrate/20260402103000_create_conversation_diagnostics_snapshots.rb`
- Create: `db/migrate/...` only if absolutely needed; prefer editing the baseline files above

**Step 1: Add `json_documents`**

- columns for installation, public id, kind, sha, bytesize, payload
- unique index on installation + kind + sha

**Step 2: Add `execution_capability_snapshots`**

- scalar identity columns
- document ref for tool surface
- jsonb for compact subagent policy

**Step 3: Add `execution_context_snapshots`**

- fingerprint
- compact `message_refs`, `import_refs`, `attachment_refs`

**Step 4: Add `execution_contracts`**

- belongs to turn
- refs to runtime/program/context/capability entities
- compact provider/origin/attachment fields

**Step 5: Replace old payload columns**

- `turns.execution_snapshot_payload` -> `execution_contract_id`
- `agent_control_report_receipts.payload` -> `report_document_id`
- `workflow_artifacts.payload` -> `document_id`
- `tool_invocations.request_payload/response_payload/error_payload` -> corresponding document refs

**Step 6: Trim diagnostics metadata expectations in schema**

- keep `metadata`
- no extra columns needed beyond current scalar fields

### Task 2: Add the new models and persistence helpers

**Files:**
- Create: `app/models/json_document.rb`
- Create: `app/models/execution_capability_snapshot.rb`
- Create: `app/models/execution_context_snapshot.rb`
- Create: `app/models/execution_contract.rb`
- Create: `app/services/json_documents/store.rb`

**Step 1: Implement `JsonDocument`**

- immutable validation
- sha/bytesize derivation
- `payload` must be a hash or array

**Step 2: Implement snapshot models**

- validations
- helper readers for tool surface and ref arrays

**Step 3: Implement `ExecutionContract`**

- validations and associations
- reader methods to compose task/identity/runtime context from associations

### Task 3: Rebuild execution snapshot creation on normalized rows

**Files:**
- Modify: `app/services/workflows/build_execution_snapshot.rb`
- Modify: `app/services/workflows/create_for_turn.rb`
- Modify: `app/services/workflows/re_enter_agent.rb`
- Modify: `app/services/workflows/resume_paused_turn.rb`
- Modify: `app/services/agent_snapshots/rebind_turn.rb`
- Modify: `app/models/turn.rb`
- Modify: `app/models/workflow_run.rb`
- Modify: `app/models/turn_execution_snapshot.rb`

**Step 1: Change the builder**

- build or find `ExecutionCapabilitySnapshot`
- build or find `ExecutionContextSnapshot`
- create `ExecutionContract`

**Step 2: Update turn persistence**

- store `execution_contract_id`
- stop writing inline execution snapshot JSON

**Step 3: Keep snapshot reader compatibility**

- adapt `TurnExecutionSnapshot` to read through `ExecutionContract`
- materialize message content and import content from canonical rows on demand

### Task 4: Normalize mailbox execution assignments

**Files:**
- Modify: `app/services/agent_control/create_execution_assignment.rb`
- Modify: `app/models/agent_control_mailbox_item.rb`
- Modify: `app/services/agent_control/serialize_mailbox_item.rb`
- Modify: `app/services/provider_execution/prepare_agent_round.rb`
- Modify: `app/services/provider_execution/tool_call_runners/agent_mediated.rb`

**Step 1: Attach execution contract refs**

- execution assignment rows reference `execution_contract_id`

**Step 2: Shrink mailbox payload**

- execution assignments keep only compact mutable extras

**Step 3: Materialize protocol payload at read time**

- `SerializeMailboxItem` expands contract + payload extras into the current
  delivery envelope

### Task 5: Normalize report receipts, tool invocations, and workflow artifacts

**Files:**
- Modify: `app/services/agent_control/report.rb`
- Modify: `app/models/agent_control_report_receipt.rb`
- Modify: `app/models/tool_invocation.rb`
- Modify: write paths that create tool invocations
- Modify: `app/models/workflow_artifact.rb`
- Modify: write paths that create workflow artifacts
- Modify: `app/services/conversation_debug_exports/build_payload.rb`

**Step 1: Store inbound reports as documents**

- `Report#create_receipt!` writes a `JsonDocument`
- receipt stores `report_document_id`

**Step 2: Move tool invocation request/response/error payloads behind document refs**

- keep public readers named `request_payload`, `response_payload`, `error_payload`
- back them with associated `JsonDocument`

**Step 3: Move workflow artifact inline JSON behind document refs**

- `WorkflowArtifact#payload` becomes a reader that resolves the document

**Step 4: Update debug export paths**

- export payloads must resolve through the new document-backed readers

### Task 6: Trim diagnostics metadata

**Files:**
- Modify: `app/services/conversation_diagnostics/recompute_turn_snapshot.rb`
- Modify: `app/services/conversation_diagnostics/recompute_conversation_snapshot.rb`
- Modify: `app/models/turn_diagnostics_snapshot.rb`
- Modify: `app/models/conversation_diagnostics_snapshot.rb`
- Modify: tests covering diagnostics payloads

**Step 1: Remove duplicated ref sections**

- drop `evidence_refs`
- drop `outlier_refs`

**Step 2: Skip empty sections**

- only persist non-empty breakdowns and summaries

### Task 7: Update tests to normalized semantics

**Files:**
- Modify: execution snapshot tests
- Modify: mailbox delivery and agent control tests
- Modify: workflow artifact tests
- Modify: tool invocation tests
- Modify: diagnostics tests

**Step 1: Replace column assertions**

- assert refs and resolved readers rather than raw inline storage

**Step 2: Add targeted document-dedup tests**

- identical tool surfaces share one `JsonDocument`
- identical capability snapshots share one `ExecutionCapabilitySnapshot`

### Task 8: Regenerate the database and schema

**Files:**
- Modify: `db/schema.rb`

**Step 1: Reset the database using the agreed sequence**

Run:

```bash
cd core_matrix
rails db:drop && rm db/schema.rb && rails db:create && rails db:migrate && rails db:reset
```

**Step 2: Verify `db/schema.rb` reflects the new normalized tables and removed columns**

### Task 9: Run full verification and acceptance

**Files:**
- Inspect: `acceptance/artifacts/*`

**Step 1: Run repository verification**

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

**Step 2: Run `bin/ci`**

Run:

```bash
cd core_matrix
bin/ci
```

**Step 3: Rerun the 2048 acceptance**

Run the acceptance flow that produces the supervisor/observation artifacts,
then inspect:

- `run-summary.json`
- `observation-final.json`
- any generated mailbox/debug artifacts

### Task 10: Final cleanup and commit

**Files:**
- Modify: any affected docs under `docs/behavior/`

**Step 1: Update behavior docs**

- document the new execution contract and document-store rules

**Step 2: Commit**

```bash
git add .
git commit -m "Normalize execution payload storage"
```
