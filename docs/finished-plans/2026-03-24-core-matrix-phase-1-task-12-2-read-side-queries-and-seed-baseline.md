# Core Matrix Task 12.2: Add Read-Side Queries And Seed Baseline

Part of `Core Matrix Kernel Milestone 4: Protocol, Publication, And Verification`.

Use this task document together with:

1. `AGENTS.md`
2. `docs/design/2026-03-24-core-matrix-kernel-greenfield-design.md`
3. `docs/finished-plans/2026-03-24-core-matrix-phase-1-kernel-greenfield-implementation-plan.md`
4. `docs/finished-plans/2026-03-24-core-matrix-phase-1-kernel-milestone-4-protocol-publication-and-verification.md`

Load this file as the detailed execution unit for Task 12.2. Treat Task Group 12 and the milestone file as ordering indexes, not as the full task body.

Reference capture for this task:

- if this task consults `references/` or external implementations, record the consulted slice and the retained conclusion, invariant, or intentional difference in this task document or another local document updated by the same execution unit
- when this task updates behavior docs, checklist docs, or other local docs, carry that conclusion into those docs instead of leaving only a bare reference path
- keep reference paths as index pointers only; restate the relevant behavior locally so this task remains understandable if the reference later drifts

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
- Create: `core_matrix/test/integration/seed_baseline_test.rb`
- Create: `core_matrix/docs/behavior/read-side-queries-and-seed-baseline.md`
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

Do not implement these items in this task:

- publication state mutations
- checklist rewrites or manual validation execution
- any human-facing page or dashboard

## Completion Record

- Status: completed
- Completion date: 2026-03-25
- Landing commit: `055aa7f` `feat: add read side queries and seed baseline`

### Landed Scope

- Added read-side queries for:
  - user-visible logical agent installation discovery
  - open human-interaction inbox/dashboard projections
  - user-private workspace listing
  - rolling-window provider usage summaries
  - execution profiling summaries
- Added an integration regression test for the seed baseline so `db/seeds.rb`
  is covered by an explicit idempotence check instead of only informal reruns.
- Updated `db/seeds.rb` so it:
  - always validates the provider catalog
  - stays safe when no installation exists
  - only reconciles the optional bundled runtime when an installation already
    exists
- Updated `core_matrix/README.md` to document the backend verification baseline
  and the bounded seed behavior without implying human-facing UI.
- Added `core_matrix/docs/behavior/read-side-queries-and-seed-baseline.md` as
  the durable local behavior source for this task.

### Verification Evidence

- Targeted tests:
  - `cd core_matrix && bin/rails test test/queries/agent_installations/visible_to_user_query_test.rb test/queries/human_interactions/open_for_user_query_test.rb test/queries/workspaces/for_user_query_test.rb test/queries/provider_usage/window_usage_query_test.rb test/queries/execution_profiling/summary_query_test.rb test/integration/seed_baseline_test.rb`
- Seed baseline command:
  - `cd core_matrix && env RAILS_ENV=test bin/rails db:seed:replant`
- Autoload check:
  - `cd core_matrix && bin/rails zeitwerk:check`
- Full project baseline:
  - `cd core_matrix && bin/brakeman --no-pager`
  - `cd core_matrix && bin/bundler-audit`
  - `cd core_matrix && bin/rubocop -f github`
  - `cd core_matrix && bun run lint:js`
  - `cd core_matrix && bin/rails db:test:prepare test`
  - `cd core_matrix && bin/rails db:test:prepare test:system`
  - `git -C .. diff --check`

### Rails And Reference Findings

- Local Rails query and model guidance remained sufficient for this task:
  query objects stayed in `app/queries`, write-side behavior stayed in services,
  and no callback or controller expansion was needed.
- The retained conclusion from the consulted Dify human-input slice is narrow:
  queryable human-input surfaces should stay anchored on durable request state
  that resumes workflow execution, not transcript reconstruction.
- The retained conclusion from the consulted OpenClaw usage slice is also
  narrow: reporting surfaces should project aggregates over tracked usage facts
  instead of introducing a separate reporting truth store.

### Carry-Forward Notes

- Future human-facing inbox or dashboard surfaces should compose these query
  objects instead of rebuilding ownership or visibility filters ad hoc in
  controllers.
- Future seed expansions should keep the current guardrail: no demo
  conversations, no sample users, and no business-agent assumptions beyond the
  existing bundled-runtime reconciliation hook.
