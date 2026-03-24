# Core Matrix Task 12: Add Publication, Query Objects, Seeds, Checklist Updates, And Final Verification

Part of `Core Matrix Kernel Phase 4: Protocol, Publication, And Verification`.

Use this task document together with:

1. `AGENTS.md`
2. `docs/plans/2026-03-24-core-matrix-kernel-greenfield-design.md`
3. `docs/plans/2026-03-24-core-matrix-kernel-greenfield-implementation-plan.md`
4. `docs/plans/2026-03-24-core-matrix-kernel-phase-4-protocol-publication-and-verification.md`
5. `docs/plans/2026-03-24-core-matrix-kernel-ui-follow-up.md`
6. `docs/checklists/2026-03-24-core-matrix-kernel-manual-validation.md`

Load this file as the detailed execution unit for Task 12. Treat the phase file as the ordering index, not the full task body.

---


**Files:**
- Create: `core_matrix/db/migrate/20260324090039_create_publications.rb`
- Create: `core_matrix/db/migrate/20260324090040_create_publication_access_events.rb`
- Create: `core_matrix/app/models/publication.rb`
- Create: `core_matrix/app/models/publication_access_event.rb`
- Create: `core_matrix/app/services/publications/publish_live.rb`
- Create: `core_matrix/app/services/publications/record_access.rb`
- Create: `core_matrix/app/services/publications/revoke.rb`
- Create: `core_matrix/app/queries/agent_installations/visible_to_user_query.rb`
- Create: `core_matrix/app/queries/human_interactions/open_for_user_query.rb`
- Create: `core_matrix/app/queries/workspaces/for_user_query.rb`
- Create: `core_matrix/app/queries/publications/live_projection_query.rb`
- Create: `core_matrix/app/queries/provider_usage/window_usage_query.rb`
- Create: `core_matrix/app/queries/execution_profiling/summary_query.rb`
- Create: `core_matrix/test/models/publication_test.rb`
- Create: `core_matrix/test/models/publication_access_event_test.rb`
- Create: `core_matrix/test/services/publications/record_access_test.rb`
- Create: `core_matrix/test/services/publications/publish_live_test.rb`
- Create: `core_matrix/test/services/publications/revoke_test.rb`
- Create: `core_matrix/test/queries/agent_installations/visible_to_user_query_test.rb`
- Create: `core_matrix/test/queries/human_interactions/open_for_user_query_test.rb`
- Create: `core_matrix/test/queries/workspaces/for_user_query_test.rb`
- Create: `core_matrix/test/queries/publications/live_projection_query_test.rb`
- Create: `core_matrix/test/queries/provider_usage/window_usage_query_test.rb`
- Create: `core_matrix/test/queries/execution_profiling/summary_query_test.rb`
- Create: `core_matrix/test/integration/publication_flow_test.rb`
- Modify: `core_matrix/db/seeds.rb`
- Modify: `core_matrix/README.md`
- Modify: `docs/checklists/2026-03-24-core-matrix-kernel-manual-validation.md`

**Step 1: Write failing unit, query, and integration tests**

Cover at least:

- publication visibility modes and revocation semantics
- `internal public` allowing any authenticated installation user while rejecting anonymous access
- `external public` allowing anonymous access through the publication slug or token
- publication access-event recording for read-only projections
- publication audit rows for enable, revoke, and visibility changes
- live projection for canonical conversation state, including visible `ConversationEvent` rows without collapsing them into transcript messages
- deterministic live projection ordering for visible `ConversationEvent` rows using stored projection metadata rather than renderer-local sorting
- global versus personal agent visibility
- open human interaction request querying for user-facing inbox or dashboard surfaces
- user-private workspace listing
- provider rolling-window usage summaries
- execution profiling summaries

`publication_flow_test.rb` should cover:

- publishing a conversation as `internal public`
- projecting it read-only for another authenticated installation user while rejecting anonymous access
- switching or publishing as `external public` and projecting it read-only anonymously
- recording an access event for the read-only projection with authenticated viewer identity when present and anonymous metadata otherwise
- revoking publication without changing ownership

**Step 2: Run the targeted tests to confirm failure**

Run:

```bash
cd core_matrix
bin/rails test test/models/publication_test.rb test/models/publication_access_event_test.rb test/services/publications/publish_live_test.rb test/services/publications/record_access_test.rb test/services/publications/revoke_test.rb test/queries/agent_installations/visible_to_user_query_test.rb test/queries/human_interactions/open_for_user_query_test.rb test/queries/workspaces/for_user_query_test.rb test/queries/publications/live_projection_query_test.rb test/queries/provider_usage/window_usage_query_test.rb test/queries/execution_profiling/summary_query_test.rb test/integration/publication_flow_test.rb
```

Expected:

- missing table, model, or query failures

**Step 3: Implement publication, queries, and seed baseline**

Rules:

- published pages are read-only by definition
- publication does not change workspace or conversation ownership
- read-side access auditing must flow through an explicit publication-access record or service, not an ad hoc controller logger
- publication live projection may render canonical transcript and visible conversation events together, but it must preserve their type distinction
- `internal public` means any authenticated `User` in the same `Installation` may read; anonymous access must fail closed and v1 does not add per-publication allowlists
- `external public` means anonymous read is allowed through the publication slug or token
- publication enable, revoke, and visibility changes must create audit rows
- live projection queries must use stored conversation-event ordering or anchoring metadata rather than renderer-local timestamp guesses
- seeds stay backend-safe and avoid business-agent assumptions beyond bundled bootstrap hooks

**Step 4: Update the manual validation checklist**

Document exact reproducible steps for at least:

- first-admin bootstrap
- invitation consume flow
- admin grant and revoke flow
- bundled Fenix auto-registration and auto-binding when configured
- agent registration, handshake, heartbeat, health, recovery, and retirement using `script/manual/dummy_agent_runtime.rb`
- machine credential rotation and revocation
- `main` auto selection, explicit candidate pinning, role-local fallback after entitlement exhaustion, and one-time recovery override
- drift-triggered manual resume and manual retry
- conversation root, branch, thread, checkpoint, archive, and unarchive
- conversation tail edit, rollback or fork editing, retry, rerun, and swipe selection
- attachment, import, summary-compaction, and visibility validation
- human form request, human task request, and open-request query validation
- canonical variable write, promotion, and transcript cursor-pagination validation through machine-facing APIs
- publication internal-public access, external-public access, access logging, and revoke

Checklist rule:

- current-batch validation must remain reproducible through shell commands, HTTP requests, Rails console actions, and `script/manual/dummy_agent_runtime.rb`
- do not add browser-only or human-facing UI validation steps to satisfy this backend completion gate

**Step 5: Run full automated verification**

Run:

```bash
cd core_matrix
bin/rails db:test:prepare
bin/rails test
bin/rails db:test:prepare test:system
bun run lint:js
bin/rubocop -f github
bin/brakeman --no-pager
bin/bundler-audit
```

Expected:

- all tests pass
- system tests pass or the suite is empty and green
- JS lint passes
- RuboCop passes
- Brakeman and Bundler Audit are clean or have documented exceptions

**Step 6: Run manual real-environment validation**

Run:

```bash
cd core_matrix
bin/dev
```

Then execute the checklist in `docs/checklists/2026-03-24-core-matrix-kernel-manual-validation.md`.

Expected:

- the documented backend flows can be reproduced in a real environment
- any pairing or M2M flow required by the checklist can be exercised end to end
- checklist notes are updated with actual outcomes and any caveats

**Step 7: Commit**

```bash
git -C .. add core_matrix/db/migrate core_matrix/app/models core_matrix/app/services/publications core_matrix/app/queries core_matrix/test/models core_matrix/test/services core_matrix/test/queries core_matrix/test/integration core_matrix/db/seeds.rb core_matrix/README.md docs/checklists/2026-03-24-core-matrix-kernel-manual-validation.md core_matrix/db/schema.rb
git -C .. commit -m "feat: add publication and backend verification baseline"
```

## Stop Point

Stop after Task 12.

Do not implement these items in this phase:

- setup wizard UI
- password/session UI
- admin dashboards
- conversation pages
- publication pages
- human-facing Turbo or Stimulus work
- Action Cable or browser realtime delivery

Human-facing deferred surfaces belong to `docs/plans/2026-03-24-core-matrix-kernel-ui-follow-up.md`. Non-UI follow-up work such as `AutomationTrigger`, recurring execution, and webhook ingress remains outside this backend kernel batch even though it is not a UI topic.
