# Core Matrix Phase 2 Task: Add Unified Capability Governance

Part of `Core Matrix Phase 2: Agent Loop Execution`.

Use this task document together with:

1. `AGENTS.md`
2. `docs/design/2026-03-24-core-matrix-agent-protocol-and-tool-surface-design.md`
3. `docs/design/2026-03-25-core-matrix-platform-phases-and-validation-design.md`
4. `docs/plans/2026-03-26-core-matrix-phase-2-plan-agent-loop-execution.md`
5. `docs/plans/2026-03-26-core-matrix-phase-2-task-mailbox-control-and-resource-close-contract.md`

Load this file as the detailed execution unit for the unified capability
governance task inside Phase 2.
Treat the milestone, sequencing, and execution-contract documents as ordering
indexes, not as the full task body.

Reference capture for this task:

- if this task consults `references/` or external implementations, record the
  consulted source section and the retained conclusion, invariant, or intentional
  difference in this task document or another local document updated by the
  same execution unit
- when this task updates behavior docs, checklist docs, or other local docs,
  carry that conclusion into those docs instead of leaving only a bare
  reference path
- keep reference paths as index pointers only; restate the relevant behavior
  locally so this task remains understandable if the reference later drifts

---

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
- Create or modify: `core_matrix/test/models/tool_binding_test.rb`
- Create or modify: `core_matrix/test/models/tool_invocation_test.rb`
- Create or modify: `core_matrix/test/services/tool_bindings/*`
- Create or modify: `core_matrix/test/services/tool_invocations/*`
- Create or modify: `core_matrix/test/requests/agent_api/capabilities_controller_test.rb`
- Modify: `core_matrix/docs/behavior/agent-registration-and-capability-handshake.md`
- Modify: `core_matrix/docs/behavior/provider-governance-models-and-services.md`
- Modify: `core_matrix/docs/behavior/agent-runtime-resource-apis.md`

**Step 1: Write failing model, service, and request tests**

Cover at least:

- `ToolDefinition`, `ToolImplementation`, `ImplementationSource`,
  `ToolBinding`, and `ToolInvocation`
- binding freeze at `AgentTaskRun` creation
- rebind only on explicit new attempt or recovery
- reserved-prefix enforcement
- whitelist-only versus replaceable policy
- one kernel-owned tool path and one agent-program-exposed tool path sharing
  the same invocation model

**Step 2: Run the targeted tests to confirm failure**

Run:

```bash
cd core_matrix
bin/rails test test/models/tool_binding_test.rb test/models/tool_invocation_test.rb test/services/tool_bindings test/services/tool_invocations test/requests/agent_api/capabilities_controller_test.rb
```

Expected:

- missing governance-model, binding, or policy failures

**Step 3: Implement unified governance**

Rules:

- breaking changes are allowed in Phase 2
- provider tools, agent-program tools, and later MCP-backed tools must share
  the same durable binding and invocation model
- binding decisions freeze when `AgentTaskRun` is created from the current
  execution snapshot
- retries keep the same binding unless recovery opens a new attempt
- policy decisions must be auditable rather than runtime-local convention

**Step 4: Update local behavior docs**

Document exact retained behavior for:

- capability-governance objects
- binding freeze point
- reserved-prefix and whitelist policy
- invocation-history persistence

**Step 5: Run the targeted tests**

Run:

```bash
cd core_matrix
bin/rails test test/models/tool_binding_test.rb test/models/tool_invocation_test.rb test/services/tool_bindings test/services/tool_invocations test/requests/agent_api/capabilities_controller_test.rb
```

Expected:

- targeted capability-governance tests pass

**Step 6: Commit**

```bash
git -C .. add core_matrix/app/models/tool_definition.rb core_matrix/app/models/tool_implementation.rb core_matrix/app/models/implementation_source.rb core_matrix/app/models/tool_binding.rb core_matrix/app/models/tool_invocation.rb core_matrix/app/models/capability_snapshot.rb core_matrix/app/models/agent_task_run.rb core_matrix/app/controllers/agent_api/capabilities_controller.rb core_matrix/app/services/tool_bindings core_matrix/app/services/tool_invocations core_matrix/app/services/agent_deployments/handshake.rb core_matrix/test/models/tool_binding_test.rb core_matrix/test/models/tool_invocation_test.rb core_matrix/test/services/tool_bindings core_matrix/test/services/tool_invocations core_matrix/test/requests/agent_api/capabilities_controller_test.rb core_matrix/docs/behavior/agent-registration-and-capability-handshake.md core_matrix/docs/behavior/provider-governance-models-and-services.md core_matrix/docs/behavior/agent-runtime-resource-apis.md
git -C .. commit -m "feat: add unified capability governance"
```

## Stop Point

Stop after one kernel tool path and one agent-program tool path share the same
governance and invocation model.

Do not implement these items in this task:

- Streamable HTTP MCP transport
- `Fenix` skills
- final manual validation
