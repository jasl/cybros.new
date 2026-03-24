# Core Matrix Task 12.2: Add Read-Side Queries And Seed Baseline

Part of `Core Matrix Kernel Phase 4: Protocol, Publication, And Verification`.

Use this task document together with:

1. `AGENTS.md`
2. `docs/plans/2026-03-24-core-matrix-kernel-greenfield-design.md`
3. `docs/plans/2026-03-24-core-matrix-kernel-greenfield-implementation-plan.md`
4. `docs/plans/2026-03-24-core-matrix-kernel-phase-4-protocol-publication-and-verification.md`

Load this file as the detailed execution unit for Task 12.2. Treat Task 12 and the phase file as ordering indexes, not as the full task body.

---

**Files:**
- Create: `core_matrix/app/queries/agent_installations/visible_to_user_query.rb`
- Create: `core_matrix/app/queries/human_interactions/open_for_user_query.rb`
- Create: `core_matrix/app/queries/workspaces/for_user_query.rb`
- Create: `core_matrix/app/queries/provider_usage/window_usage_query.rb`
- Create: `core_matrix/app/queries/execution_profiling/summary_query.rb`
- Create: `core_matrix/test/queries/agent_installations/visible_to_user_query_test.rb`
- Create: `core_matrix/test/queries/human_interactions/open_for_user_query_test.rb`
- Create: `core_matrix/test/queries/workspaces/for_user_query_test.rb`
- Create: `core_matrix/test/queries/provider_usage/window_usage_query_test.rb`
- Create: `core_matrix/test/queries/execution_profiling/summary_query_test.rb`
- Modify: `core_matrix/db/seeds.rb`
- Modify: `core_matrix/README.md`

**Step 1: Write failing query tests**

Cover at least:

- global versus personal agent visibility
- open human interaction request querying for inbox or dashboard surfaces
- user-private workspace listing
- provider rolling-window usage summaries
- execution profiling summaries

**Step 2: Run the targeted tests to confirm failure**

Run:

```bash
cd core_matrix
bin/rails test test/queries/agent_installations/visible_to_user_query_test.rb test/queries/human_interactions/open_for_user_query_test.rb test/queries/workspaces/for_user_query_test.rb test/queries/provider_usage/window_usage_query_test.rb test/queries/execution_profiling/summary_query_test.rb
```

Expected:

- missing query failures

**Step 3: Implement read-side queries and seed baseline**

Rules:

- global and personal agent visibility must stay distinct
- open human interaction queries remain read-side only and must not mutate request state
- workspace listing must preserve private ownership semantics
- seeds must stay backend-safe and avoid business-agent assumptions beyond bundled bootstrap hooks
- `README.md` updates should document the backend verification baseline without describing nonexistent UI

**Step 4: Run the targeted tests**

Run:

```bash
cd core_matrix
bin/rails test test/queries/agent_installations/visible_to_user_query_test.rb test/queries/human_interactions/open_for_user_query_test.rb test/queries/workspaces/for_user_query_test.rb test/queries/provider_usage/window_usage_query_test.rb test/queries/execution_profiling/summary_query_test.rb
```

Expected:

- targeted tests pass

**Step 5: Commit**

```bash
git -C .. add core_matrix/app/queries core_matrix/test/queries core_matrix/db/seeds.rb core_matrix/README.md
git -C .. commit -m "feat: add read side queries and seed baseline"
```

## Stop Point

Stop after read-side queries and backend-safe seed updates pass their tests.

Do not implement these items in this subtask:

- publication state mutations
- checklist rewrites or manual validation execution
- any human-facing page or dashboard
