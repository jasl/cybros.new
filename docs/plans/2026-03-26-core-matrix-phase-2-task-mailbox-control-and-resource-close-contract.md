# Core Matrix Phase 2 Task: Mailbox Control And Resource Close Contract

Part of `Core Matrix Phase 2: Agent Loop Execution`.

## Purpose

Land the mailbox-first control contract that replaces the older claim-first
execution design.

This task should establish:

- durable mailbox items for agent control work
- `AgentTaskRun` as the workflow-owned execution resource
- `poll + WebSocket + response piggyback` as equivalent delivery paths
- explicit target routing for assignments and close requests
- generic resource close commands and acknowledgements
- `message_retry`, `delivery_retry`, and `execution_attempt_retry` rules that
  later tasks can safely consume

## Scope

This task is responsible for the control contract only. It should not yet
prove full provider execution breadth or conversation close behavior.

### In Scope

- `AgentTaskRun`
- mailbox item persistence and delivery semantics
- `execution_assignment`
- `execution_started`
- `execution_progress`
- `execution_complete`
- `execution_fail`
- `execution_interrupted`
- `resource_close_request`
- `resource_close_acknowledged`
- `resource_closed`
- `resource_close_failed`
- `agent_poll`
- `deployment_health_report`
- session presence and control-activity state
- `message_retry`, `delivery_retry`, and `execution_attempt_retry` rules

### Out Of Scope

- provider-backed model execution breadth
- archive and delete lifecycle transitions
- human-interaction wait handoff details
- subagent orchestration breadth
- MCP implementation breadth

## Files

- Create: `core_matrix/app/models/agent_task_run.rb`
- Likely create: `core_matrix/app/models/agent_control_mailbox_item.rb`
- Likely create: `core_matrix/app/controllers/agent_api/control_controller.rb`
- Likely create: `core_matrix/app/services/agent_control/*`
- Modify: `core_matrix/app/models/execution_lease.rb`
- Modify: `core_matrix/app/models/agent_deployment.rb`
- Modify: `core_matrix/config/routes.rb`
- Create: `core_matrix/test/models/agent_task_run_test.rb`
- Create: `core_matrix/test/models/agent_control_mailbox_item_test.rb`
- Create: `core_matrix/test/requests/agent_api/control_poll_test.rb`
- Create: `core_matrix/test/requests/agent_api/execution_delivery_test.rb`
- Create: `core_matrix/test/requests/agent_api/resource_close_test.rb`
- Likely create: `core_matrix/test/services/agent_control/*`
- Modify: `core_matrix/test/services/leases/*`
- Modify: `core_matrix/docs/behavior/agent-runtime-resource-apis.md`
- Modify: `core_matrix/docs/behavior/workflow-artifacts-node-events-and-process-runs.md`

## Required Behavior

### Mailbox Item Rules

- mailbox items persist durable control work
- `WebSocket` and `poll` carry the same item envelope
- `poll` must remain a complete fallback path
- response piggyback may deliver pending mailbox items when useful
- mailbox items are not a generic broker feature; they are targeted control
  items owned by the kernel
- assignments must be targetable to eligible deployment scope
- close requests must be targetable to the current known holder when one exists
- `execution_started` is the durable assignment-acceptance point and must
  establish holder or lease ownership

### Retry Rules

- `message_retry` is idempotent by `message_id`
- `delivery_retry` increments `delivery_no` and does not imply a new business
  attempt
- `execution_attempt_retry` increments `attempt_no`
- late or duplicate reports must not mutate superseded durable state

### Close Rules

- generic resource-close commands must be durable
- closable runtime resources must persist close request and close outcome fields
- close requests outrank queued retry work
- a close request must not rely on a reverse callback from the kernel

## Verification

Cover at least:

- mailbox item creation, leasing, expiry, and redelivery
- idempotent duplicate report handling
- stale or superseded report rejection
- `agent_poll` returning queued mailbox items
- `WebSocket`-independent fallback behavior
- resource close acknowledgement and terminal close outcomes

## Stop Point

Stop after the mailbox contract, `AgentTaskRun`, and resource-close control
surface are implemented and tested.

Do not continue here into:

- archive and delete state transitions
- provider-backed execution breadth
- wait-state and human-interaction recovery behavior
