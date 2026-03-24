# Core Matrix Task 11.2: Add Runtime Resource APIs

Part of `Core Matrix Kernel Phase 4: Protocol, Publication, And Verification`.

Use this task document together with:

1. `AGENTS.md`
2. `docs/plans/2026-03-24-core-matrix-kernel-greenfield-design.md`
3. `docs/plans/2026-03-24-core-matrix-kernel-greenfield-implementation-plan.md`
4. `docs/plans/2026-03-24-core-matrix-kernel-phase-4-protocol-publication-and-verification.md`
5. `docs/plans/2026-03-24-core-matrix-agent-protocol-and-tool-surface-design.md`

Load this file as the detailed execution unit for Task 11.2. Treat Task 11 and the phase file as ordering indexes, not as the full task body.

---

**Files:**
- Create: `core_matrix/app/controllers/agent_api/conversation_transcripts_controller.rb`
- Create: `core_matrix/app/controllers/agent_api/conversation_variables_controller.rb`
- Create: `core_matrix/app/controllers/agent_api/workspace_variables_controller.rb`
- Create: `core_matrix/app/controllers/agent_api/human_interactions_controller.rb`
- Create: `core_matrix/app/queries/conversation_transcripts/list_query.rb`
- Create: `core_matrix/app/queries/conversation_variables/get_query.rb`
- Create: `core_matrix/app/queries/conversation_variables/mget_query.rb`
- Create: `core_matrix/app/queries/conversation_variables/list_query.rb`
- Create: `core_matrix/app/queries/conversation_variables/resolve_query.rb`
- Create: `core_matrix/app/queries/workspace_variables/get_query.rb`
- Create: `core_matrix/app/queries/workspace_variables/mget_query.rb`
- Create: `core_matrix/app/queries/workspace_variables/list_query.rb`
- Create: `core_matrix/test/requests/agent_api/conversation_transcripts_test.rb`
- Create: `core_matrix/test/requests/agent_api/conversation_variables_test.rb`
- Create: `core_matrix/test/requests/agent_api/workspace_variables_test.rb`
- Create: `core_matrix/test/requests/agent_api/human_interactions_test.rb`
- Create: `core_matrix/test/queries/conversation_transcripts/list_query_test.rb`
- Create: `core_matrix/test/queries/conversation_variables/get_query_test.rb`
- Create: `core_matrix/test/queries/conversation_variables/mget_query_test.rb`
- Create: `core_matrix/test/queries/conversation_variables/list_query_test.rb`
- Create: `core_matrix/test/queries/conversation_variables/resolve_query_test.rb`
- Create: `core_matrix/test/queries/workspace_variables/get_query_test.rb`
- Create: `core_matrix/test/queries/workspace_variables/mget_query_test.rb`
- Create: `core_matrix/test/queries/workspace_variables/list_query_test.rb`
- Create: `core_matrix/test/integration/agent_runtime_resource_api_test.rb`
- Modify: `core_matrix/config/routes.rb`

**Step 1: Write failing request, query, and integration tests**

Cover at least:

- cursor-paginated canonical transcript listing
- conversation variable `get`, `mget`, `list`, and `resolve` behavior
- workspace variable `get`, `mget`, and `list` behavior
- variable write and promotion intent handling through machine-facing APIs
- human interaction request creation through machine-facing APIs
- request and response schemas for transcript, variable, and human-interaction surfaces
- published contract still separating `protocol_methods` from `tool_catalog`

**Step 2: Run the targeted tests to confirm failure**

Run:

```bash
cd core_matrix
bin/rails test test/requests/agent_api/conversation_transcripts_test.rb test/requests/agent_api/conversation_variables_test.rb test/requests/agent_api/workspace_variables_test.rb test/requests/agent_api/human_interactions_test.rb test/queries/conversation_transcripts/list_query_test.rb test/queries/conversation_variables/get_query_test.rb test/queries/conversation_variables/mget_query_test.rb test/queries/conversation_variables/list_query_test.rb test/queries/conversation_variables/resolve_query_test.rb test/queries/workspace_variables/get_query_test.rb test/queries/workspace_variables/mget_query_test.rb test/queries/workspace_variables/list_query_test.rb test/integration/agent_runtime_resource_api_test.rb
```

Expected:

- missing route, controller, or query failures

**Step 3: Implement runtime-resource APIs**

Rules:

- transcript listing must return the canonical visible transcript only and support cursor pagination
- variable APIs must expose explicit `get`, `mget`, `list`, and `resolve` semantics rather than ambiguous read verbs
- machine-facing variable writes and promotions remain kernel-declared intent boundaries, not direct agent-owned database writes
- machine-facing human-interaction creation must create workflow-owned request resources and projection events through kernel services
- keep controller code thin and route naming resource-oriented even while logical operation IDs stay `snake_case`

**Step 4: Run the targeted tests**

Run:

```bash
cd core_matrix
bin/rails test test/requests/agent_api/conversation_transcripts_test.rb test/requests/agent_api/conversation_variables_test.rb test/requests/agent_api/workspace_variables_test.rb test/requests/agent_api/human_interactions_test.rb test/queries/conversation_transcripts/list_query_test.rb test/queries/conversation_variables/get_query_test.rb test/queries/conversation_variables/mget_query_test.rb test/queries/conversation_variables/list_query_test.rb test/queries/conversation_variables/resolve_query_test.rb test/queries/workspace_variables/get_query_test.rb test/queries/workspace_variables/mget_query_test.rb test/queries/workspace_variables/list_query_test.rb test/integration/agent_runtime_resource_api_test.rb
```

Expected:

- targeted tests pass

**Step 5: Commit**

```bash
git -C .. add core_matrix/app/controllers/agent_api core_matrix/config/routes.rb core_matrix/app/queries/conversation_transcripts core_matrix/app/queries/conversation_variables core_matrix/app/queries/workspace_variables core_matrix/test/requests core_matrix/test/queries core_matrix/test/integration
git -C .. commit -m "feat: add runtime resource apis"
```

## Stop Point

Stop after transcript, variable, and human-interaction APIs pass their tests.

Do not implement these items in this subtask:

- machine-credential rotation or revocation
- bootstrap, outage handling, or recovery
- publication read models
