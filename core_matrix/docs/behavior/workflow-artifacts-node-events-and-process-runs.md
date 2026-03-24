# Workflow Artifacts, Node Events, And Process Runs

## Purpose

Task 10.1 adds the first workflow-owned runtime resource layer beyond the DAG
shape itself.

This task does not project runtime state into `ConversationEvent`, human inbox
surfaces, or lease coordination yet. It establishes the workflow-local durable
resources that later tasks build on:

- `WorkflowArtifact`
- `WorkflowNodeEvent`
- `ProcessRun`

## Workflow Artifacts

- `WorkflowArtifact` belongs to exactly one installation, workflow run, and
  workflow node.
- Artifacts use explicit storage modes rather than ad hoc payload shapes:
  - `inline_json`
  - `attached_file`
- `inline_json` persists structured payload in `payload` and does not attach a
  file.
- `attached_file` persists canonical metadata in `payload` and requires a
  `has_one_attached :file` attachment.
- Artifact ownership stays workflow-scoped: a node may emit an artifact, but
  the artifact remains queryable through the owning workflow run.

## Workflow Node Events

- `WorkflowNodeEvent` is the append-only workflow-local execution stream.
- Every event belongs to one installation, workflow run, and workflow node.
- Events are ordered by a node-local `ordinal` that is unique per workflow
  node.
- Task 10.1 keeps `event_kind` open-ended, but the first landed runtime path
  uses `status` events for process lifecycle replay.
- `WorkflowNodeEvent` remains the kernel trace surface; later tasks may project
  selected runtime state into `ConversationEvent` only when that state is
  intentionally user-visible.

## Process Runs

- `ProcessRun` is now a first-class runtime resource instead of an opaque tool
  side effect.
- Every process run belongs to:
  - one installation
  - one workflow node
  - one execution environment
  - one conversation
  - one turn
  - optionally one originating transcript-bearing `Message`
- Task 10.1 intentionally does not add a second persisted `workflow_run_id` on
  `ProcessRun`; workflow-run ownership is derived through the owning node, while
  `conversation_id` and `turn_id` are redundantly persisted for operational
  filtering exactly as required by the design.
- v1 kinds are explicit and validated:
  - `turn_command`
  - `background_service`
- v1 lifecycle states are explicit and validated:
  - `running`
  - `stopped`
  - `failed`
  - `lost`

## Timeout And Ownership Rules

- `turn_command` requires `timeout_seconds`.
- `background_service` must not carry a bounded timeout.
- `conversation_id` must match the owning workflow run conversation.
- `turn_id` must match the owning workflow run turn.
- `origin_message_id`, when present, must belong to the same conversation and
  turn as the process run.
- `started_at` is defaulted during validation for new records so model-level
  validation and service-created rows share the same timestamp baseline.
- non-running process states require `ended_at`; running process states must not
  carry `ended_at`.

## Start And Stop Services

- `Processes::Start` is the application-service boundary for opening a workflow
  process resource.
- Start currently:
  - materializes one `ProcessRun`
  - derives `conversation` and `turn` from the owning workflow run
  - appends one `WorkflowNodeEvent` with `event_kind=status` and
    `payload.state=running`
  - records an `AuditLog` row when the workflow node metadata marks the process
    as policy-sensitive or the service input overrides that flag
- `Processes::Stop` is the application-service boundary for terminating a
  running process resource.
- Stop currently:
  - requires the process run to still be `running`
  - transitions the process to `stopped`
  - stamps `ended_at`
  - records `stop_reason` in process metadata
  - appends one `WorkflowNodeEvent` with `event_kind=status` and
    `payload.state=stopped`

## Failure Modes

- attached-file artifacts reject missing attachments
- node events reject duplicate ordinals within the same workflow node
- process runs reject workflow-turn or workflow-conversation mismatches
- process runs reject bounded timeouts on background services
- process runs reject missing bounded timeouts on turn commands
- stop requests reject non-running process runs instead of silently mutating
  terminal rows

## Rails And Reference Findings

- Local Rails association guides were used here to keep ownership explicit
  through `belongs_to` foreign-key relationships and model-level consistency
  checks instead of inferring cross-record identity from loose IDs alone.
- Local Rails validation guides were used again for the
  `errors.add` plus `ActiveRecord::RecordInvalid` service-boundary pattern used
  in `Processes::Stop`.
- Local Active Storage guides confirmed the `has_one_attached` model pattern is
  the right durable boundary for file-backed workflow artifacts in this task.
- No `references/` implementation was treated as authoritative for Task 10.1;
  the landed behavior is derived from the local design and plan documents.
