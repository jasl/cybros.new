# CoreMatrix Agent UI And Runtime Follow-Up

**Goal:** Capture the work intentionally deferred from the current backend-only `core_matrix` implementation slice.

**Status:** Not in scope for the first end-to-end automated backend build.

## Deferred Areas

- routes, controllers, request contracts, and response serializers
- live streaming transport for turn progress and command output
- Action Cable or alternative realtime delivery choices
- views, components, composer UX, tree navigation UI, and message browsing
- JavaScript state management and the eventual UI framework integration
- presenter/view-model shaping for transcript and workflow state
- background job orchestration for workflow runners, process polling, subagent polling, and reconciliation
- provider/runtime adapters for model execution, tool execution, subprocess supervision, and subagent integration

## Preconditions

Do not start this document's work until all of the following are true:

- the backend schema and core models are complete
- the first backend service layer is implemented and tested
- attachment persistence is working through Active Storage
- workflow and resource control-plane semantics are stable
- the UI framework decision is finalized
- the runtime adapter boundary is agreed

## Expected Inputs From The Backend Slice

The deferred work assumes the backend slice already provides:

- durable conversation tree, transcript, workflow, and resource tables
- service objects for root creation, branching, turn start/queue/steer, workflow mutation, and process/subagent control
- query objects for tree navigation, visible transcript assembly, and ready-node selection
- backend tests that lock down invariants before any transport or UI code is added

## Implementation Order For The Follow-Up Slice

1. choose the UI framework and realtime transport
2. define controller and serializer contracts on top of the backend services
3. add progress/event delivery for turn and process updates
4. build tree navigation, transcript rendering, composer state, and approval UX
5. add background runners and reconciliation jobs for long-lived execution resources
6. implement provider/runtime adapters and runtime health reporting

## Guardrails

- do not redesign the backend schema from the UI layer
- do not bypass application services with controller-level business logic
- do not couple realtime transport details into the core domain models
- do not introduce runtime-specific fields into user-visible transcript records unless they are required by a validated product requirement
