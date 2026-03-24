# Core Matrix Task 12.1: Add Publication Model And Live Projection

Part of `Core Matrix Kernel Milestone 4: Protocol, Publication, And Verification`.

Use this task document together with:

1. `AGENTS.md`
2. `docs/design/2026-03-24-core-matrix-kernel-greenfield-design.md`
3. `docs/plans/2026-03-24-core-matrix-kernel-greenfield-implementation-plan.md`
4. `docs/plans/2026-03-24-core-matrix-kernel-milestone-4-protocol-publication-and-verification.md`

Load this file as the detailed execution unit for Task 12.1. Treat Task Group 12 and the milestone file as ordering indexes, not as the full task body.

Reference capture for this task:

- if this task consults `references/` or external implementations, record the consulted slice and the retained conclusion, invariant, or intentional difference in this task document or another local document updated by the same execution unit
- when this task updates behavior docs, checklist docs, or other local docs, carry that conclusion into those docs instead of leaving only a bare reference path
- keep reference paths as index pointers only; restate the relevant behavior locally so this task remains understandable if the reference later drifts

---

**Files:**
- Create: `core_matrix/db/migrate/20260324090039_create_publications.rb`
- Create: `core_matrix/db/migrate/20260324090040_create_publication_access_events.rb`
- Create: `core_matrix/app/models/publication.rb`
- Create: `core_matrix/app/models/publication_access_event.rb`
- Create: `core_matrix/app/services/publications/publish_live.rb`
- Create: `core_matrix/app/services/publications/record_access.rb`
- Create: `core_matrix/app/services/publications/revoke.rb`
- Create: `core_matrix/app/queries/publications/live_projection_query.rb`
- Create: `core_matrix/test/models/publication_test.rb`
- Create: `core_matrix/test/models/publication_access_event_test.rb`
- Create: `core_matrix/test/services/publications/publish_live_test.rb`
- Create: `core_matrix/test/services/publications/record_access_test.rb`
- Create: `core_matrix/test/services/publications/revoke_test.rb`
- Create: `core_matrix/test/queries/publications/live_projection_query_test.rb`
- Create: `core_matrix/test/integration/publication_flow_test.rb`

**Step 1: Write failing model, service, query, and integration tests**

Cover at least:

- publication visibility modes and revocation semantics
- `internal public` allowing any authenticated installation user while rejecting anonymous access
- `external public` allowing anonymous access through the publication slug or token
- publication access-event recording for read-only projections
- publication audit rows for enable, revoke, and visibility changes
- live projection for canonical conversation state, including visible `ConversationEvent` rows without collapsing them into transcript messages
- deterministic live projection ordering for visible `ConversationEvent` rows using stored projection metadata rather than renderer-local sorting

**Step 2: Run the targeted tests to confirm failure**

Run:

```bash
cd core_matrix
bin/rails test test/models/publication_test.rb test/models/publication_access_event_test.rb test/services/publications/publish_live_test.rb test/services/publications/record_access_test.rb test/services/publications/revoke_test.rb test/queries/publications/live_projection_query_test.rb test/integration/publication_flow_test.rb
```

Expected:

- missing table, model, or query failures

**Step 3: Implement publication and live projection**

Rules:

- published projections are read-only by definition
- publication does not change workspace or conversation ownership
- read-side access auditing must flow through an explicit publication-access record or service
- publication live projection may render canonical transcript and visible conversation events together, but it must preserve their type distinction
- `internal public` means any authenticated `User` in the same `Installation` may read; anonymous access must fail closed
- `external public` means anonymous read is allowed through the publication slug or token
- publication enable, revoke, and visibility changes must create audit rows
- live projection queries must use stored conversation-event ordering or anchoring metadata rather than renderer-local timestamp guesses

**Step 4: Run the targeted tests**

Run:

```bash
cd core_matrix
bin/rails db:migrate
bin/rails test test/models/publication_test.rb test/models/publication_access_event_test.rb test/services/publications/publish_live_test.rb test/services/publications/record_access_test.rb test/services/publications/revoke_test.rb test/queries/publications/live_projection_query_test.rb test/integration/publication_flow_test.rb
```

Expected:

- targeted tests pass

**Step 5: Commit**

```bash
git -C .. add core_matrix/db/migrate core_matrix/app/models/publication.rb core_matrix/app/models/publication_access_event.rb core_matrix/app/services/publications core_matrix/app/queries/publications core_matrix/test/models core_matrix/test/services core_matrix/test/queries core_matrix/test/integration core_matrix/db/schema.rb
git -C .. commit -m "feat: add publication and live projection"
```

## Stop Point

Stop after publication state, access logging, and live projection pass their tests.

Do not implement these items in this task:

- user-facing publication pages
- workspace or agent visibility queries
- final automated or manual verification
