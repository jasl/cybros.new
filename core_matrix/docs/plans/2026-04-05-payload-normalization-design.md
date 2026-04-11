# Payload Normalization Design

## Goal

Normalize large duplicated JSON payloads across `core_matrix` so hot operational
rows keep compact facts and refs, while large immutable JSON moves into
first-class document and snapshot models.

This design is intentionally destructive. It does not preserve compatibility,
does not backfill, and assumes the database can be reset.

## Why This Exists

The current schema stores the same frozen execution data in multiple places:

- `turns.execution_snapshot_payload`
- `agent_control_mailbox_items.payload`
- `agent_control_report_receipts.payload`

Those rows duplicate the same tool surface, context envelope, provider context,
and execution ids. The same pattern appears in other places with raw JSON payload
ownership being unclear.

The result is avoidable write amplification, larger row sizes, and a weak model
for future auditability because "what is canonical" and "what is just a frozen
copy" are mixed together.

## Design Principles

### 1. One canonical owner for raw content

Raw transcript text stays on `Message` and `ConversationSummarySegment`.
Large JSON reports, tool payloads, and artifact bodies move to one immutable
document model.

### 2. Frozen execution contracts store refs, not content copies

Execution-facing snapshots must freeze membership and capability state, not copy
message or summary text into every row.

### 3. Hot rows keep compact facts only

Mailbox items, turns, receipts, diagnostics snapshots, and observation frames
should keep only:

- scalar status fields
- public-id or foreign-key refs
- compact arrays of refs
- compact derived facts that are expensive to recompute

They should not inline large request or response bodies.

### 4. Audit evidence remains durable

Auditability is preserved by storing immutable JSON documents referenced from
operational rows. We do not lose the evidence; we stop copying it everywhere.

### 5. Heterogeneous JSON is allowed only when it is canonical and small

Examples that may remain inline:

- small feature/config snapshots
- wait metadata that is truly workflow-owned
- small health/session metadata
- node metadata that is domain state rather than copied transport payload

### 6. Derived presentation rows do not own duplicated state

If one row already owns the frozen assessment or contract, adjacent rows that
exist only for presentation or transcript-like display should store only their
own content and refs.

Examples:

- observation frames own frozen bundle and assessment data
- observation messages store rendered sidechat text and frame refs, not another
  copy of supervisor state
- workflow nodes store a ref to large tool call payloads, not the raw call body

This rule prevents "small" secondary tables from quietly reintroducing the same
duplication pattern after the main snapshot table has already been normalized.

## New Core Models

### `JsonDocument`

Purpose: immutable, content-addressed storage for large JSON payloads.

This is the common document model for:

- raw execution reports
- tool invocation request/response/error bodies
- workflow artifact JSON bodies
- large frozen tool surfaces

Suggested fields:

- `installation_id`
- `public_id`
- `document_kind`
- `content_sha256`
- `content_bytesize`
- `payload`
- timestamps

Rules:

- immutable after creation
- deduplicated per installation by `document_kind + content_sha256`
- only JSON documents go here

This name is intentionally common and explicit. The model stores JSON documents,
not arbitrary "payload blobs".

## Applied Refactors

The current implementation already applies this design to several important
paths:

- turn execution snapshots, agent control mailbox items, and report receipts use
  first-class execution contracts and document-backed evidence
- workflow node tool calls are stored via `tool_call_document_id` instead of
  inline metadata payloads
- tool bindings keep structured governance columns and `runtime_state` only for
  mutable session state
- observation frames own compact frozen evidence; observation messages no
  longer duplicate supervisor state or runtime headers

### `ExecutionCapabilitySnapshot`

Purpose: one deduplicated frozen capability surface for execution.

Suggested fields:

- `installation_id`
- `public_id`
- `fingerprint`
- `program_version_fingerprint`
- `profile_key`
- `subagent`
- `subagent_depth`
- `subagent_connection_id`
- `parent_subagent_connection_id`
- `owner_conversation_id`
- `tool_surface_document_id`
- `subagent_policy_snapshot`
- timestamps

This snapshot owns the execution-visible tool surface and subagent capability
shape. It is deduplicated by fingerprint instead of being copied onto every turn
and mailbox item.

### `ExecutionContextSnapshot`

Purpose: freeze turn context membership without copying raw content.

Suggested fields:

- `installation_id`
- `public_id`
- `fingerprint`
- `projection_fingerprint`
- `message_refs`
- `import_refs`
- `attachment_refs`
- timestamps

`message_refs`, `import_refs`, and `attachment_refs` contain compact refs and
minimal presentation metadata only. They do not contain message text, summary
text, or raw file bodies.

This stays as compact JSON arrays because:

- the data is already ref-only
- row counts are low
- the shape is snapshot-specific rather than reusable domain state

### `ExecutionContract`

Purpose: replace `turns.execution_snapshot_payload` with a first-class turn-level
frozen execution contract.

Suggested fields:

- `installation_id`
- `turn_id`
- `public_id`
- `agent_snapshot_id`
- `execution_runtime_id`
- `selected_input_message_id`
- `selected_output_message_id`
- `execution_capability_snapshot_id`
- `execution_context_snapshot_id`
- `provider_context`
- `turn_origin`
- `attachment_manifest`
- `model_input_attachments`
- `attachment_diagnostics`
- timestamps

This name is more precise than `execution_snapshot_payload`.

The contract is the frozen agreement between orchestration and execution:

- which context membership is visible
- which capability surface is visible
- which provider/model settings were resolved
- which attachments are in play

It does not duplicate data already owned by `Turn`, `Conversation`, `Message`,
or `AgentSnapshot`.

## Existing Tables After Refactor

### `turns`

Replace:

- remove `execution_snapshot_payload`

Add:

- `execution_contract_id`

Keep inline:

- `origin_payload`
- `resolved_config_snapshot`
- `resolved_model_selection_snapshot`
- `feature_policy_snapshot`

These are turn-owned and relatively small.

### `agent_control_mailbox_items`

Keep the table.

Add:

- `execution_contract_id`

Keep `payload`, but redefine its purpose:

- execution assignments store only compact delivery extras
- close requests and other request types continue to store small item-specific
  request bodies

For `execution_assignment`, `payload` should only contain:

- `task_payload`
- `prior_tool_results`

The large envelope is rendered from the `ExecutionContract` at serialization
time.

### `agent_control_report_receipts`

Replace:

- remove inline `payload`

Add:

- `report_document_id`

Keep inline:

- `method_id`
- `logical_work_id`
- `attempt_no`
- `result_code`

The raw inbound report body becomes immutable evidence in `JsonDocument`.

### `tool_invocations`

Replace:

- `request_payload`
- `response_payload`
- `error_payload`

Add:

- `request_document_id`
- `response_document_id`
- `error_document_id`

Keep:

- `metadata`

Rationale: the raw tool bodies are audit evidence; the invocation row should
store compact status and refs.

### `workflow_artifacts`

Replace:

- `payload`

Add:

- `document_id`

Update `storage_mode`:

- `json_document`
- `attached_file`

This keeps the artifact row as a locator and policy boundary rather than a large
JSON bucket.

### `conversation_diagnostics_snapshots` and `turn_diagnostics_snapshots`

Keep the tables and their metric columns.

Trim `metadata` so it stores only compact breakdowns that are:

- not already stored in scalar columns
- not trivially derivable from scalar columns
- not empty

Remove duplicated "outlier refs" and "evidence refs" that can be derived from
dedicated columns and associations.

### `workflow_runs`

Keep:

- `wait_reason_payload`
- `resume_metadata`

But treat them as workflow-owned domain state, not transport storage. They must
remain compact and must not embed full task or transcript payloads.

### `workflow_nodes`

Keep `metadata` inline.

It is node-owned domain state, not frozen transport duplication. The current
average size is acceptable, though individual node types should still avoid
embedding large raw documents.

### `tool_bindings`

Keep `binding_payload` inline for now.

It is canonical binding state, relatively small, and not the same duplication
problem as turn/mailbox/report payloads.

## Read Model Compatibility

Public product APIs should keep the same external shapes where practical.

That means:

- `Turn#execution_snapshot` still returns a snapshot-like object
- `WorkflowRun#execution_snapshot` still delegates
- mailbox serialization still emits the current execution-assignment envelope

The difference is where that data comes from:

- message text is rebuilt from canonical `Message` rows
- import text is rebuilt from canonical `ConversationSummarySegment` or source
  `Message` rows
- tool surface is read from a shared `JsonDocument`
- receipts and artifacts resolve bodies through document refs

The database becomes normalized even if the runtime-facing shape stays familiar.

## Creation Flow

### Turn / Workflow entry

1. resolve model selection
2. build or find `ExecutionCapabilitySnapshot`
3. build or find `ExecutionContextSnapshot`
4. create `ExecutionContract`
5. attach the contract to the turn
6. create workflow run and initial task
7. create mailbox assignment that references the contract

### Mailbox serialization

1. load mailbox item
2. if item is `execution_assignment`, load `ExecutionContract`
3. materialize the current protocol envelope from the contract plus mailbox
   `task_payload` and `prior_tool_results`
4. return the expanded runtime-facing payload

### Program runtime protocol

Program-runtime mailbox items should not mirror the entire frozen execution
snapshot.

Use a narrower protocol projection instead:

- `round_context` for current prepared messages and import refs
- `agent_context` for profile/subagent metadata and allowed tool names
- `provider_context` for model/budget/runtime execution settings
- `runtime_context` for protocol identity

Do not send these on the program wire when they are not consumed by the
external runtime:

- `conversation_projection.prior_tool_results`
- full `capability_projection.tool_surface` schemas

Instead:

- Core Matrix keeps `prior_tool_results` locally and appends them when building
  the next provider request
- the program runtime returns `visible_tool_names`
- Core Matrix maps those names back onto the canonical frozen tool surface

### Report receipt

1. store raw inbound report body in `JsonDocument`
2. create `AgentControlReportReceipt` with compact facts and `report_document_id`
3. handlers continue to work from the in-memory request payload

## Column Classification Rules For Future Development

When adding a new JSON field, the author must decide which class it belongs to:

### Canonical inline state

Use inline JSON only when the row itself is the true owner and the data is
small.

### Frozen snapshot

Use a dedicated snapshot model when the data represents a reusable frozen
contract or context.

### Immutable document

Use `JsonDocument` when the data is large raw evidence, request/response bodies,
or shared frozen JSON that would otherwise be copied into many rows.

### Not allowed

Do not inline:

- raw transcript text copied from `Message`
- raw summary text copied from `ConversationSummarySegment`
- the same tool catalog or tool surface on multiple hot rows
- full transport request/response envelopes on mailbox or receipt rows

## Migration Strategy

Because compatibility is intentionally dropped:

- edit baseline migrations in place
- regenerate the database from scratch
- regenerate `db/schema.rb`
- update factories, services, and tests to the new schema directly

## Expected Outcome

After this refactor:

- turns own compact execution contracts, not giant JSON payload blobs
- mailbox items stop duplicating execution snapshots
- report receipts stop storing full report bodies inline
- tool invocations and workflow artifacts store document refs
- auditability improves because raw evidence has a single immutable owner
- future payload growth becomes a schema design question rather than a hidden
  row-size regression
