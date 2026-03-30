# Core Matrix Phase 2 Task: Add Streamable HTTP MCP Under Unified Governance

Part of `Core Matrix Phase 2: Agent Loop Execution`.

Use this task document together with:

1. `AGENTS.md`
2. `docs/research-notes/2026-03-25-core-matrix-phase-2-runtime-loop-and-mcp-research-note.md`
3. `docs/plans/2026-03-26-core-matrix-phase-2-plan-agent-loop-execution.md`
4. `docs/plans/2026-03-25-core-matrix-phase-2-task-unified-capability-governance.md`
5. `docs/finished-plans/2026-03-25-core-matrix-phase-2-task-fenix-runtime-surface-and-execution-hooks.md`

Load this file as the detailed execution unit for the Streamable HTTP MCP task
inside Phase 2.
Treat the milestone, sequencing, governance, and `Fenix` runtime documents as
ordering indexes, not as the full task body.

Status note (`2026-03-30`):

- current code scan did not find an MCP service layer, governed MCP invocation
  history, or Streamable HTTP MCP integration tests
- treat this task as still greenfield after `Task E1` lands

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
- Create or modify: `core_matrix/app/services/mcp/*`
- Create or modify: `core_matrix/app/models/tool_invocation.rb`
- Create or modify: `core_matrix/app/models/tool_binding.rb`
- Modify: `core_matrix/app/services/tool_invocations/*`
- Modify: `core_matrix/app/controllers/agent_api/capabilities_controller.rb`
- Create or modify: `core_matrix/test/services/mcp/*`
- Create or modify: `core_matrix/test/integration/streamable_http_mcp_flow_test.rb`
- Modify: `core_matrix/docs/behavior/provider-governance-models-and-services.md`
- Modify: `core_matrix/docs/behavior/agent-runtime-resource-apis.md`

**Step 1: Write failing service and integration tests**

Cover at least:

- one Streamable HTTP MCP capability path under the same binding model as other
  tools
- session-aware transport state
- invocation history and attempt recording
- transport, protocol, and semantic failure classification
- retry, wait, or recovery behavior under MCP failure

**Step 2: Run the targeted tests to confirm failure**

Run:

```bash
cd core_matrix
bin/rails test test/services/mcp test/integration/streamable_http_mcp_flow_test.rb
```

Expected:

- missing MCP client, session, or governance failures

**Step 3: Implement one governed Streamable HTTP MCP path**

Rules:

- breaking changes are allowed in Phase 2
- MCP must enter through the same durable governance model as other tools
- session state should be explicit and auditable
- transport handling must remain Rails-implementation-neutral
- one real path is enough; do not widen into generic connector ecosystems

**Step 4: Update local behavior docs**

Document exact retained behavior for:

- Streamable HTTP MCP session handling
- MCP invocation under unified governance
- failure classification and recovery expectations

**Step 5: Run the targeted tests**

Run:

```bash
cd core_matrix
bin/rails test test/services/mcp test/integration/streamable_http_mcp_flow_test.rb
```

Expected:

- targeted MCP-governance tests pass

**Step 6: Run one real MCP validation pass**

Expected:

- one real MCP-backed capability succeeds under the governed invocation model
- failure handling is visible and auditable if the transport is interrupted

**Step 7: Commit**

```bash
git -C .. add core_matrix/app/services/mcp core_matrix/app/models/tool_invocation.rb core_matrix/app/models/tool_binding.rb core_matrix/app/services/tool_invocations core_matrix/app/controllers/agent_api/capabilities_controller.rb core_matrix/test/services/mcp core_matrix/test/integration/streamable_http_mcp_flow_test.rb core_matrix/docs/behavior/provider-governance-models-and-services.md core_matrix/docs/behavior/agent-runtime-resource-apis.md
git -C .. commit -m "feat: add streamable http mcp governance"
```

## Stop Point

Stop after one real Streamable HTTP MCP capability path works under unified
governance.

Do not implement these items in this task:

- broader plugin or extension systems
- WebSocket transport as canonical execution delivery
- `Fenix` skill catalogs
