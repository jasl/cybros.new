# Human Interactions And Conversation Events

## Purpose

Task 10.2 adds the first workflow-owned human-interaction runtime layer and the
first conversation-local operational projection layer.

This task does not introduce canonical variables, lease control, or subagent
resources. It establishes:

- workflow-owned human-interaction requests as durable runtime state
- append-only `ConversationEvent` rows as the user-visible projection surface
- default same-workflow resume for blocking human-interaction resolution

## Human Interaction Requests

- `HumanInteractionRequest` uses STI with exactly three supported subclasses in
  v1:
  - `ApprovalRequest`
  - `HumanFormRequest`
  - `HumanTaskRequest`
- Every request belongs to one installation, workflow run, workflow node,
  conversation, and turn.
- `conversation_id` and `turn_id` are redundantly persisted on the request row
  for direct querying, but they must still match the owning workflow run.
- The base lifecycle is explicit and validated:
  - `open`
  - `resolved`
  - `canceled`
  - `timed_out`
- Structured request input lives in `request_payload`.
- Structured outcome data lives in `result_payload`.
- Outcome kind is explicit through `resolution_kind` rather than being inferred
  from free-form payloads.

## Subclass Rules

- `ApprovalRequest` requires `request_payload["approval_scope"]`.
- `ApprovalRequest` only accepts `approved` or `denied` resolution outcomes
  when it enters the resolved state.
- `HumanFormRequest` requires an `input_schema` hash and only accepts a
  `defaults` value when it is also a hash.
- `SubmitForm` validates required fields from
  `request_payload["input_schema"]["required"]` against the merged defaults and
  submitted payload before resolving the request.
- `HumanTaskRequest` requires human-readable `instructions`.
- `HumanTaskRequest.open` remains directly queryable through the base
  lifecycle-state enum so inbox-style lists do not need transcript
  reconstruction.

## Blocking Wait And Resume

- `HumanInteractions::Request` is the application-service boundary for creating
  human-interaction requests.
- Blocking requests set the owning `WorkflowRun` into:
  - `wait_state = waiting`
  - `wait_reason_kind = human_interaction`
  - `blocking_resource_type = HumanInteractionRequest`
  - `blocking_resource_id = <request id>`
- Blocking requests therefore pause scheduler selection on the same workflow
  run rather than spawning a new turn or a new workflow run.
- `HumanInteractions::ResolveApproval`, `SubmitForm`, and `CompleteTask` all
  resume the same workflow run by clearing that wait state when the request is
  still the active blocking resource.
- Expired open requests time out in place and also clear the same blocking wait
  state instead of silently staying open forever.

## Conversation Events

- `ConversationEvent` is the append-only operational projection surface for a
  conversation.
- `ConversationEvent` is not a transcript-bearing `Message`.
- Creating or revising a conversation event never mutates `messages`,
  selected-input pointers, selected-output pointers, or transcript legality
  rules.
- Every event belongs to one installation and one conversation.
- Events may carry an optional turn anchor through `turn_id`.
- Events may carry an optional polymorphic `source`, which Task 10.2 uses to
  point back to the originating `HumanInteractionRequest`.

## Projection Ordering And Replaceable Streams

- `projection_sequence` is unique per conversation and defines deterministic
  append-only ordering.
- `ConversationEvents::Project` is the application-service boundary that
  assigns the next projection sequence.
- Replaceable live-projection streams use:
  - `stream_key`
  - `stream_revision`
- Each new revision in a stream still appends a new `ConversationEvent` row.
- `ConversationEvent.live_projection` collapses a stream to its latest revision
  while preserving the original insertion position of that stream in the live
  projection order.
- Replay, audit, and diagnostics can still inspect the full append-only event
  history because no earlier row is overwritten.

## Human Interaction Projection

- Human-interaction creation projects `human_interaction.opened`.
- Human-interaction resolution projects `human_interaction.resolved`.
- Human-interaction expiry projects `human_interaction.timed_out`.
- All three projections reuse the same stream key
  `human_interaction_request:<request id>` so a live surface can replace one
  visible approval/form/task card in place while storage remains append-only.

## Failure Modes

- unsupported base-class `HumanInteractionRequest` rows are rejected
- request rows reject conversation or turn drift away from the owning workflow
  run
- open requests reject premature `resolution_kind`, `resolved_at`, or
  non-empty `result_payload`
- form submission rejects missing required fields before request resolution
- repeated approval resolution rejects non-open requests
- conversation events reject duplicate `projection_sequence` values inside one
  conversation
- `stream_revision` must be paired with `stream_key`; neither field is treated
  as free-form optional noise

## Rails And Reference Findings

- Local Rails STI guidance confirmed Task 10.2 should keep all request types in
  one table with `type` as the discriminator and subclass-specific validation in
  the Ruby subclasses.
- Local Rails validation guidance again supported the `errors.add` plus
  `ActiveRecord::RecordInvalid` pattern for request-resolution and
  submission-validation failures.
- A narrow Dify sanity check showed Dify persists paused workflow state and
  resumes the same workflow execution after human input instead of starting a
  brand new run. Core Matrix intentionally keeps the simpler v1 shape of:
  workflow-owned request row + workflow-run wait state + same-workflow resume,
  while still preserving structured result data on the request before resuming.
- No reference implementation was treated as authoritative for this task; the
  landed contract is defined by the local design, tests, and checklist update.
