# Recoverable Failure Step Resume Design

## Goal

Make provider-side, runtime-side, and transport-side external failures non-terminal at the workflow node level so the same step can pause in `waiting` and later resume, while preserving terminal failure for true implementation errors.

## Scope

- `core_matrix` workflow execution semantics
- provider-backed turn steps
- step-level waiting and resume behavior
- failure classification surfaced to workflow state and user-facing diagnostics

Out of scope for this slice:

- APP-layer product choices between "resume same step" and "start a new run"
- provider-specific billing UX

## Current status

The main state model is already implemented in `core_matrix`:

- `Turn.lifecycle_state` supports `waiting`
- `WorkflowRun.wait_reason_kind` includes `external_dependency_blocked`
- `ProviderExecution::FailureClassification` maps provider, transport, and
  protocol failures into explicit categories
- `Workflows::BlockNodeForFailure`, `Workflows::ResumeBlockedStep`, and
  `Workflows::ResumeBlockedStepJob` carry the blocked-step lifecycle

The remaining work is mostly closure work:

- broaden integration coverage for recoverable provider and contract failures
- remove dead assertions and stale plan assumptions
- keep behavior docs aligned with the implemented scheduler semantics

## Core Decisions

### 1. Failure categories are explicit

Failures are classified into three categories:

- `implementation_error`
  - Internal invariant bugs, serialization bugs, impossible states, and unknown errors that cannot be safely classified.
  - These remain terminal.
- `contract_error`
  - Invalid tool call contract, invalid arguments, invalid execution/program report contract, and similar protocol violations.
  - These are non-terminal at the workflow-node level and enter a retryable waiting state.
- `external_dependency_blocked`
  - Provider rate limits, exhausted credits, upstream outages, expired provider auth, runtime session loss, transport failures, and tool infrastructure outages.
  - These are business-equivalent to pause and enter waiting, not failure.

### 2. Workflow node is the recovery boundary

Recovery is defined at the `WorkflowNode` level.

- A blocked node transitions `running -> waiting`
- Recovery transitions `waiting -> queued -> running`
- Terminal failures still use `running -> failed`

The user-visible `Turn` and aggregate `WorkflowRun` mirror this blocked state, but the recovery unit is always the current step.

### 3. Automatic retry is modeled as waiting

Automatic retry is not a hidden `retry_job` mechanism anymore.

Instead:

- the node is marked waiting
- the workflow stores a structured wait reason
- `next_retry_at` is persisted in wait metadata
- a scheduler resumes the blocked node when due

This keeps product state and scheduler state aligned.

### 4. Turn state must represent waiting

`Turn.lifecycle_state` gains `waiting`.

This is required so a conversation shows the correct state while the active step is blocked by an external dependency. A blocked turn is not failed and should not look active forever.

## Failure mapping

### Implementation errors

These remain terminal:

- `internal_invariant_broken`
- `internal_serialization_failed`
- `internal_unexpected_error`

Result:

- `workflow_node.lifecycle_state = "failed"`
- `turn.lifecycle_state = "failed"`
- `workflow_run.lifecycle_state = "failed"`

### Contract errors

These become waiting with retry semantics:

- `invalid_tool_call_contract`
- `invalid_tool_arguments`
- `unknown_tool_reference`
- `invalid_execution_report_contract`
- `invalid_program_response_contract`

Result:

- `workflow_node.lifecycle_state = "waiting"`
- `turn.lifecycle_state = "waiting"`
- `workflow_run.wait_state = "waiting"`
- `workflow_run.wait_reason_kind = "retryable_failure"`

### External dependency blocked

These become waiting with pause semantics:

- `provider_rate_limited`
- `provider_credits_exhausted`
- `provider_overloaded`
- `provider_unreachable`
- `provider_auth_expired`
- `agent_connection_unavailable`
- `execution_session_unavailable`
- `program_transport_failed`
- `execution_transport_failed`
- `tool_transport_failed`
- `tool_runtime_unavailable`
- `tool_invocation_timeout`

Result:

- `workflow_node.lifecycle_state = "waiting"`
- `turn.lifecycle_state = "waiting"`
- `workflow_run.wait_state = "waiting"`
- `workflow_run.wait_reason_kind = "external_dependency_blocked"`

## Wait payload contract

`workflow_run.wait_reason_payload` should carry structured recovery metadata:

- `failure_category`
- `failure_kind`
- `retry_scope = "step"`
- `resume_mode = "same_step"`
- `retry_strategy`
  - `automatic`
  - `manual`
- `auto_retryable`
- `attempt_no`
- `max_auto_retries`
- `next_retry_at`
- `last_error_summary`
- `provider_handle`
- `model_ref`
- `provider_request_id`
- optional session identifiers for runtime failures

## Scheduling model

### New blocking path

Introduce a unified service that blocks the current workflow step instead of directly failing it:

- `Workflows::BlockNodeForFailure`

Responsibilities:

- classify the failure
- choose terminal failure vs waiting
- update `workflow_node`, `turn`, and `workflow_run`
- append structured workflow node events

### New resume path

Introduce a unified step-resume service:

- `Workflows::ResumeBlockedStep`

Responsibilities:

- validate that the node is currently blocked
- restore `workflow_run` to ready
- restore `turn` to active
- move the blocked node back to queued
- let the normal dispatcher continue

### Automatic retry driver

Introduce a dedicated resume job:

- `Workflows::ResumeBlockedStepJob`

Responsibilities:

- wake only the specific blocked workflow run scheduled for automatic retry
- verify the workflow is still waiting on the same blocked workflow node
- invoke `ResumeBlockedStep`

## Existing paths to remove or replace

- `ExecuteNodeJob` rescue-based `retry_job` for `AdmissionRefused`
- provider request failures going straight to `PersistTurnStepFailure`
- implicit provider defer semantics hidden only in workflow node status events

## Compatibility stance

This is a destructive reset. Compatibility is not required.

The implementation may:

- change enums
- change waiting semantics
- replace retry scheduling paths
- rewrite related tests and behavior docs

## Validation goals

The final implementation should prove:

- provider rate limit does not fail the workflow; it waits and can auto-resume
- provider credits exhausted does not fail the workflow; it waits for manual recovery
- provider auth expiry does not fail the workflow; it waits for manual recovery
- invalid tool call contract does not fail the workflow; it waits under retryable failure
- internal unexpected error still fails terminally
- the same workflow node can be resumed rather than requiring a new run
