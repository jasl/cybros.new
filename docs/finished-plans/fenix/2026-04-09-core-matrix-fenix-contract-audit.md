# CoreMatrix <-> Fenix Contract Audit

## Scope

This audit covers the active machine-facing contracts between `core_matrix` and
`agents/fenix`:

- runtime registration and capability discovery
- agent-plane mailbox delivery and report handling
- agent request / response exchange
- execution-runtime-plane close and process-runtime control

This document is a working inventory for implementation and test repair. It is
not a product spec.

## Contract Families

### 1. Runtime Registration And Capability Discovery

Definition:

- `agents/fenix/README.md`
- `agents/fenix/app/services/runtime/pairing_manifest.rb`
- `core_matrix/test/requests/agent_api/capabilities_test.rb`
- `core_matrix/test/requests/agent_api/health_test.rb`

Implementation:

- `agents/fenix/config/routes.rb`
- `agents/fenix/app/controllers/runtime_manifests_controller.rb`
- `agents/fenix/app/services/runtime/pairing_manifest.rb`
- `core_matrix/app/controllers/agent_api/health_controller.rb`
- `core_matrix/app/controllers/agent_api/capabilities_controller.rb`

Existing tests:

- `agents/fenix/test/integration/runtime_manifest_test.rb`
- `agents/fenix/test/services/runtime/control_client_test.rb`
- `core_matrix/test/requests/agent_api/capabilities_test.rb`
- `core_matrix/test/requests/agent_api/health_test.rb`

Audit note:

- `protocol_methods` in the manifest include registration/capability methods
  like `agent_health` and `capabilities_handshake`; these are not
  `control/report` methods and should not be audited as mailbox terminal
  reports.

Status:

- `green` for the current boundary and request coverage shape

### 2. Program-Plane Mailbox Delivery

Definition:

- `agents/fenix/README.md`
- `core_matrix/docs/plans/2026-04-05-payload-normalization-design.md`
- `core_matrix/docs/behavior/identifier-policy.md`
- `shared/fixtures/contracts/core_matrix_fenix_execution_assignment.json`

Implementation:

- `core_matrix/app/controllers/agent_api/control_controller.rb`
- `core_matrix/app/services/agent_control/poll.rb`
- `core_matrix/app/services/agent_control/create_execution_assignment.rb`
- `core_matrix/app/services/agent_control/serialize_mailbox_item.rb`
- `core_matrix/app/models/agent_control_mailbox_item.rb`
- `agents/fenix/app/services/runtime/control_plane.rb`
- `agents/fenix/app/services/runtime/mailbox_pump.rb`
- `agents/fenix/app/services/runtime/mailbox_worker.rb`
- `agents/fenix/app/services/runtime/execute_mailbox_item.rb`
- `agents/fenix/app/services/runtime/assignments/dispatch_mode.rb`
- `agents/fenix/app/services/runtime/assignments/deterministic_tool.rb`

Existing tests:

- `core_matrix/test/services/agent_control/create_execution_assignment_test.rb`
- `core_matrix/test/services/agent_control/serialize_mailbox_item_test.rb`
- `core_matrix/test/models/agent_control_mailbox_item_test.rb`
- `core_matrix/test/services/agent_control/poll_test.rb`
- `core_matrix/test/requests/agent_api/control_poll_test.rb`
- `core_matrix/test/requests/agent_api/execution_delivery_test.rb`
- `agents/fenix/test/services/runtime/mailbox_pump_test.rb`
- `agents/fenix/test/services/runtime/mailbox_worker_test.rb`
- `agents/fenix/test/services/runtime/execute_mailbox_item_test.rb`
- `agents/fenix/test/services/runtime/assignments/dispatch_mode_test.rb`
- `agents/fenix/test/services/runtime/assignments/deterministic_tool_test.rb`

Status:

- `green` for the current public delivery/report boundary

### 3. Agent-Program Request Exchange

Definition:

- `core_matrix/docs/plans/2026-04-05-payload-normalization-design.md`
  - `Program runtime protocol`
- `agents/fenix/README.md`

Implementation:

- `core_matrix/app/services/agent_control/create_agent_request.rb`
- `core_matrix/app/services/agent_control/handle_agent_report.rb`
- `core_matrix/app/services/provider_execution/agent_request_exchange.rb`
- `core_matrix/app/services/provider_execution/prepare_agent_round.rb`
- `core_matrix/app/services/provider_execution/tool_call_runners/agent_mediated.rb`
- `agents/fenix/app/services/runtime/prepare_round.rb`
- `agents/fenix/app/services/runtime/execute_tool.rb`
- `agents/fenix/app/services/runtime/execute_mailbox_item.rb`

Existing tests:

- `core_matrix/test/services/agent_control/create_agent_request_test.rb`
- `core_matrix/test/services/agent_control/handle_agent_report_test.rb`
- `core_matrix/test/services/provider_execution/agent_request_exchange_test.rb`
- `core_matrix/test/services/provider_execution/agent_request_exchange_perf_test.rb`
- `core_matrix/test/services/provider_execution/prepare_agent_round_test.rb`
- `core_matrix/test/services/provider_execution/tool_call_runners/agent_mediated_test.rb`
- `agents/fenix/test/services/runtime/prepare_round_test.rb`
- `agents/fenix/test/services/runtime/execute_tool_test.rb`
- `agents/fenix/test/services/runtime/execute_mailbox_item_test.rb`

Status:

- `green` for the currently declared request kinds

Audit note:

- `Fenix` now validates the full conversation-control envelope:
  - mailbox `request_kind` must match the declared conversation-control request
    kind
  - conversation targets must remain conversation-scoped
  - subagent guidance must declare a matching `subagent_connection_id`
  - status refresh rejects stray guidance content
- `core_matrix` now persists structured `response_payload` / `error_payload`
  on linked `ConversationControlRequest.result_payload`

### 4. Executor-Plane Close And Process Runtime Control

Definition:

- `agents/fenix/README.md`
- `core_matrix/docs/behavior/identifier-policy.md`

Implementation:

- `core_matrix/app/controllers/executor_api/control_controller.rb`
- `core_matrix/app/services/agent_control/poll.rb`
- `core_matrix/app/services/agent_control/report.rb`
- `core_matrix/app/services/agent_control/handle_runtime_resource_report.rb`
- `core_matrix/app/services/agent_control/handle_close_report.rb`
- `agents/fenix/app/services/runtime/mailbox_worker.rb`
- `agents/fenix/app/services/processes/manager.rb`

Existing tests:

- `core_matrix/test/requests/executor_api/control_poll_test.rb`
- `core_matrix/test/requests/agent_api/resource_close_test.rb`
- `core_matrix/test/requests/agent_api/process_runtime_test.rb`
- `agents/fenix/test/services/runtime/mailbox_worker_test.rb`

Status:

- `green` for the currently declared close/process contract

## Findings Repaired In This Branch

### Finding 1: Missing request-level coverage for agent terminal reports

Original problem:

- `core_matrix` has service-level tests for `agent_completed` and
  `agent_failed`
- the public `/agent_api/control/report` contract does not currently have
  request-level tests for those method ids

Risk:

- controller wiring, auth scoping, structured receipt reconstruction, or
  piggyback mailbox behavior could regress without detection

Repair:

- add request specs for `agent_completed`
- add request specs for `agent_failed`

### Finding 2: Fenix does not fully implement the declared supervision mailbox request surface

Original problem:

- `core_matrix/app/services/agent_control/create_agent_request.rb`
  explicitly supports:
  - `prepare_round`
  - `execute_tool`
  - `supervision_status_refresh`
  - `supervision_guidance`
- `core_matrix/app/services/conversation_control/dispatch_request.rb` can
  dispatch the latter two to the active agent
- `agents/fenix/app/services/runtime/execute_mailbox_item.rb` only
  handles:
  - `prepare_round`
  - `execute_tool`

Risk:

- the public mailbox contract is wider than the Fenix implementation
- supervision control requests can be created and delivered, but Fenix will
  terminal-fail them instead of honoring the contract

Repair:

- define the correct Fenix handling for:
  - `supervision_status_refresh`
  - `supervision_guidance`
- add direct runtime tests
- add request-level CoreMatrix tests proving the public control-report boundary
  handles the resulting terminal reports

### Finding 3: Missing mailbox-item bridge coverage for execute_tool

Original problem:

- `Fenix::Runtime::ExecuteProgramTool` has unit coverage
- `core_matrix` has agent-exchange coverage
- `Fenix::Runtime::ExecuteMailboxItem` does not have direct coverage that an
  `agent_request` mailbox item for `execute_tool` produces the
  correct `agent_completed` / `agent_failed` report envelope

Risk:

- the runtime-local request execution can drift from the mailbox terminal-report
  contract while lower-level units still pass

Repair:

- add `ExecuteMailboxItem` tests for:
  - `execute_tool` success
  - `execute_tool` visibility failure

### Finding 4: The public manifest understated the agent requests surface

Original problem:

- `Fenix` runtime manifest `program_contract.methods` still declared only:
  - `prepare_round`
  - `execute_tool`
- the runtime now also supports:
  - `supervision_status_refresh`
  - `supervision_guidance`

Risk:

- external registration metadata understated the actual mailbox request
  contract
- future capability negotiation or operator inspection could make decisions
  from stale metadata

Repair:

- extend `program_contract.methods` to list both supervision request kinds
- update runtime-manifest integration coverage

### Finding 5: Linked conversation-control requests dropped structured runtime outcomes

Original problem:

- `HandleAgentReport` only copied mailbox status and timestamps back to
  `ConversationControlRequest.result_payload`
- structured `response_payload` / `error_payload` from Fenix terminal reports
  were discarded

Risk:

- the control audit trail could not explain what the runtime acknowledged or
  why it failed
- request-level report coverage could still pass while losing the only durable
  runtime result body for supervision requests

Repair:

- persist structured `response_payload` and `error_payload` on linked
  `ConversationControlRequest.result_payload`
- add service and request tests for both completion and failure paths
- add a symmetric `AgentControl::Report` storage test for
  `agent_failed`

### Finding 6: Supervision mailbox requests omitted scoped runtime user identity

Original problem:

- `CreateConversationControlRequest` did not populate
  `payload.runtime_context.user_id`
- these mailbox items have no `execution_contract`, so serialization could not
  reconstruct the user scope later

Risk:

- `agent + user` scoped runtime features could not rely on the same
  runtime-context contract for supervision requests
- poll and serialization produced a narrower envelope than execution
  assignments

Repair:

- inject `runtime_context.agent_id` and `runtime_context.user_id` at
  conversation-control mailbox creation time
- add request and serialization tests that assert the scoped public ids are
  present

### Finding 7: Agent-agent freshness gating had no direct specification test

Original problem:

- `ValidateAgentReportFreshness` enforced the lease/attempt/logical work
  contract
- the project had only indirect freshness coverage through higher-level report
  handlers

Risk:

- future changes could weaken or bypass the freshness contract without a direct
  failing test

Repair:

- add focused freshness tests for accepted leased reports and stale superseded
  reports

## Follow-Up Resolution

The earlier supervision-guidance watchpoint is now closed.

Completed `supervision_guidance` requests now flow through a shared durable
seam:

- `core_matrix` projects acknowledged guidance from
  `ConversationControlRequest` audit rows
- `ProviderExecution::BuildWorkContextView` injects that projection into
  `work_context_view["supervisor_guidance"]`
- `prepare_round` carries the projection into the agent payload
- `Fenix::Prompts::Assembler` renders a dedicated `Supervisor Guidance`
  section while preserving the raw durable-state JSON block

Subagent guidance is routed from the owner conversation audit trail to the
child conversation runtime by targeting the child `SubagentConnection.public_id`.

Reference design:

- `docs/plans/2026-04-09-supervision-guidance-durable-state.md`
