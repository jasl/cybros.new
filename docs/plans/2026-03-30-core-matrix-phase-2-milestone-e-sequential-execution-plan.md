# Core Matrix Phase 2 Milestone E Sequential Execution Plan

> **For Codex:** REQUIRED SUB-SKILL: Use [$executing-plans](/Users/jasl/.codex/skills/executing-plans/SKILL.md) to implement this plan task-by-task.

**Goal:** Land the remaining capability-governance and Streamable HTTP MCP work so governed tool use is durable, auditable, and usable in a real loop.

**Architecture:** Extend the current capability snapshot and effective tool catalog into a durable governance layer instead of adding another parallel catalog model. All tool use, whether kernel-owned, agent-exposed, or MCP-backed, should flow through the same binding and invocation records.

**Tech Stack:** Ruby on Rails, Active Record, Minitest, Streamable HTTP MCP integration, `bin/dev`

---

## Required Inputs

- `AGENTS.md`
- `docs/design/2026-03-30-core-matrix-phase-2-sequential-execution-design.md`
- `docs/plans/2026-03-26-core-matrix-phase-2-plan-agent-loop-execution.md`
- `docs/plans/2026-03-25-core-matrix-phase-2-task-unified-capability-governance.md`
- `docs/plans/2026-03-25-core-matrix-phase-2-task-streamable-http-mcp-under-governance.md`
- `docs/checklists/2026-03-24-core-matrix-kernel-manual-validation.md`

## Execution Contract

- do not start Milestone `E` until Milestone `D` exit criteria are actually met
- keep the binding freeze point on `AgentTaskRun` boundaries unless the active
  task docs are updated
- do not implement MCP as a bypass around the governance layer

## Batch 1: Milestone E Preflight And E1

### Task 1: Run the Milestone E preflight

**Files:**
- Review: `docs/plans/2026-03-25-core-matrix-phase-2-task-unified-capability-governance.md`
- Review: `docs/plans/2026-03-25-core-matrix-phase-2-task-streamable-http-mcp-under-governance.md`
- Review: `core_matrix/app/models/capability_snapshot.rb`
- Review: `core_matrix/app/models/agent_task_run.rb`

Confirm:

- no unexpected `ToolDefinition`, `ToolImplementation`, `ToolBinding`, or
  `ToolInvocation` model layer already exists
- the real MCP validation target is concrete enough to exercise later under
  `bin/dev`

Stop if:

- current code already includes a conflicting governance model that would
  change the retained design boundary

### Task 2: Execute E1 with TDD

**Files:**
- Modify or create: `core_matrix/app/models/tool_definition.rb`
- Modify or create: `core_matrix/app/models/tool_implementation.rb`
- Modify or create: `core_matrix/app/models/implementation_source.rb`
- Modify or create: `core_matrix/app/models/tool_binding.rb`
- Modify or create: `core_matrix/app/models/tool_invocation.rb`
- Modify: `core_matrix/app/models/capability_snapshot.rb`
- Modify: `core_matrix/app/models/agent_task_run.rb`
- Modify: `core_matrix/app/controllers/agent_api/capabilities_controller.rb`
- Modify or create: `core_matrix/app/services/tool_bindings/*`
- Modify or create: `core_matrix/app/services/tool_invocations/*`
- Modify: `core_matrix/app/services/agent_deployments/handshake.rb`
- Modify or create: `core_matrix/test/models/tool_binding_test.rb`
- Modify or create: `core_matrix/test/models/tool_invocation_test.rb`
- Modify or create: `core_matrix/test/services/tool_bindings/*`
- Modify or create: `core_matrix/test/services/tool_invocations/*`
- Modify or create: `core_matrix/test/requests/agent_api/capabilities_controller_test.rb`
- Modify: `core_matrix/docs/behavior/agent-registration-and-capability-handshake.md`
- Modify: `core_matrix/docs/behavior/provider-governance-models-and-services.md`
- Modify: `core_matrix/docs/behavior/agent-runtime-resource-apis.md`

Run first:

```bash
cd core_matrix
bin/rails test test/models/tool_binding_test.rb test/models/tool_invocation_test.rb test/services/tool_bindings test/services/tool_invocations test/requests/agent_api/capabilities_controller_test.rb
```

Expected before implementation:

- failure for the missing durable governance model

Then implement only the E1 scope recorded in the task doc:

- `ToolDefinition`, `ToolImplementation`, `ImplementationSource`,
  `ToolBinding`, and `ToolInvocation`
- binding freeze at `AgentTaskRun` boundaries
- reserved-prefix and whitelist policy
- one kernel-owned tool path and one agent-program-exposed tool path under the
  same model

Run after implementation:

```bash
cd core_matrix
bin/rails test test/models/tool_binding_test.rb test/models/tool_invocation_test.rb test/services/tool_bindings test/services/tool_invocations test/requests/agent_api/capabilities_controller_test.rb
```

Expected after implementation:

- the E1 targeted suite passes

## Batch 2: E1 Audit And E2

### Task 3: Audit E1 before continuing

**Files:**
- Review: `core_matrix/app/models/tool_binding.rb`
- Review: `core_matrix/app/models/tool_invocation.rb`
- Review: `core_matrix/app/models/agent_task_run.rb`
- Review: `docs/checklists/2026-03-24-core-matrix-kernel-manual-validation.md`

Confirm:

- binding decisions are durable and auditable
- invocation history does not split into special cases by tool source
- the checklist now contains a governed tool-invocation scenario

Stop if:

- the only working implementation bypasses the governance layer for one source
  of tools

### Task 4: Execute E2 with TDD

**Files:**
- Modify or create: `core_matrix/app/services/mcp/*`
- Modify or create: `core_matrix/app/models/tool_invocation.rb`
- Modify or create: `core_matrix/app/models/tool_binding.rb`
- Modify: `core_matrix/app/services/tool_invocations/*`
- Modify: `core_matrix/app/controllers/agent_api/capabilities_controller.rb`
- Modify or create: `core_matrix/test/services/mcp/*`
- Modify or create: `core_matrix/test/integration/streamable_http_mcp_flow_test.rb`
- Modify: `core_matrix/docs/behavior/provider-governance-models-and-services.md`
- Modify: `core_matrix/docs/behavior/agent-runtime-resource-apis.md`
- Modify: `docs/checklists/2026-03-24-core-matrix-kernel-manual-validation.md`

Run first:

```bash
cd core_matrix
bin/rails test test/services/mcp test/integration/streamable_http_mcp_flow_test.rb
```

Expected before implementation:

- failure for the missing governed MCP client, session, or integration flow

Then implement only the E2 scope recorded in the task doc:

- one governed Streamable HTTP MCP capability path
- auditable session state
- invocation history through the same governance model
- durable failure classification and recovery behavior

Run after implementation:

```bash
cd core_matrix
bin/rails test test/services/mcp test/integration/streamable_http_mcp_flow_test.rb
```

Expected after implementation:

- the E2 targeted suite passes

## Batch 3: Integrated Milestone E Verification

### Task 5: Run integrated Milestone E verification

**Files:**
- Review: `core_matrix/docs/behavior/provider-governance-models-and-services.md`
- Review: `docs/checklists/2026-03-24-core-matrix-kernel-manual-validation.md`

Run:

```bash
cd core_matrix
bin/rails test test/models/tool_binding_test.rb test/models/tool_invocation_test.rb test/services/tool_bindings test/services/tool_invocations test/services/mcp test/requests/agent_api/capabilities_controller_test.rb test/integration/streamable_http_mcp_flow_test.rb test/services/runtime_capabilities/compose_for_conversation_test.rb
```

Expected:

- the integrated Milestone E regression set passes

### Task 6: Run one real governed MCP and tool validation pass

**Files:**
- Modify: `docs/checklists/2026-03-24-core-matrix-kernel-manual-validation.md`

Validate and record:

- one governed tool invocation in a real loop
- one governed Streamable HTTP MCP call in a real loop
- the observable durable records needed later for final acceptance

Expected:

- the checklist contains exact operator steps and evidence fields for both
  governed paths

## Milestone E Exit Criteria

- E1 and E2 targeted suites pass
- integrated Milestone E regression set passes
- the manual checklist contains exact governed tool and governed MCP scenarios
- one real governed MCP path is known to be executable under `bin/dev`
- no unresolved blocker remains for Milestone `F`

## Must-Stop Conditions

- the only feasible MCP design would create a second invocation history model
- a real MCP path cannot be specified without inventing new product behavior
- governed tool calls require exposing internal numeric ids at agent-facing
  boundaries
