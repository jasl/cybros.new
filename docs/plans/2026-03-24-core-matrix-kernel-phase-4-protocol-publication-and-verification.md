# Core Matrix Kernel Phase 4: Protocol, Publication, And Verification

Use this phase document together with:

1. `AGENTS.md`
2. `docs/plans/2026-03-24-core-matrix-kernel-greenfield-design.md`
3. `docs/plans/2026-03-24-core-matrix-kernel-greenfield-implementation-plan.md`
4. `docs/plans/2026-03-24-core-matrix-kernel-ui-follow-up.md`
5. `docs/checklists/2026-03-24-core-matrix-kernel-manual-validation.md`

This phase owns Tasks 11-12:

- agent protocol boundaries, runtime resource APIs, bootstrap, recovery, recovery-time selector overrides, and contract tests
- publication, query objects, seeds, checklist updates, and final verification

Apply the shared guardrails and phase-gate audits from the implementation-plan index.

---
### Task 11: Implement Agent Protocol Boundaries, Runtime Resource APIs, Contract Tests, Bootstrap, And Recovery

**Files:**
- Create: `core_matrix/app/controllers/agent_api/base_controller.rb`
- Create: `core_matrix/app/controllers/agent_api/registrations_controller.rb`
- Create: `core_matrix/app/controllers/agent_api/heartbeats_controller.rb`
- Create: `core_matrix/app/controllers/agent_api/health_controller.rb`
- Create: `core_matrix/app/controllers/agent_api/capabilities_controller.rb`
- Create: `core_matrix/app/controllers/agent_api/conversation_transcripts_controller.rb`
- Create: `core_matrix/app/controllers/agent_api/conversation_variables_controller.rb`
- Create: `core_matrix/app/controllers/agent_api/workspace_variables_controller.rb`
- Create: `core_matrix/app/controllers/agent_api/human_interactions_controller.rb`
- Create: `core_matrix/app/services/agent_deployments/handshake.rb`
- Create: `core_matrix/app/services/agent_deployments/reconcile_config.rb`
- Create: `core_matrix/app/services/agent_deployments/bootstrap.rb`
- Create: `core_matrix/app/services/agent_deployments/rotate_machine_credential.rb`
- Create: `core_matrix/app/services/agent_deployments/revoke_machine_credential.rb`
- Create: `core_matrix/app/services/agent_deployments/retire.rb`
- Create: `core_matrix/app/services/agent_deployments/mark_unavailable.rb`
- Create: `core_matrix/app/services/agent_deployments/auto_resume_workflows.rb`
- Create: `core_matrix/app/services/workflows/manual_resume.rb`
- Create: `core_matrix/app/services/workflows/manual_retry.rb`
- Create: `core_matrix/app/queries/conversation_transcripts/list_query.rb`
- Create: `core_matrix/app/queries/conversation_variables/get_query.rb`
- Create: `core_matrix/app/queries/conversation_variables/mget_query.rb`
- Create: `core_matrix/app/queries/conversation_variables/list_query.rb`
- Create: `core_matrix/app/queries/conversation_variables/resolve_query.rb`
- Create: `core_matrix/app/queries/workspace_variables/get_query.rb`
- Create: `core_matrix/app/queries/workspace_variables/mget_query.rb`
- Create: `core_matrix/app/queries/workspace_variables/list_query.rb`
- Create: `core_matrix/script/manual/dummy_agent_runtime.rb`
- Create: `core_matrix/test/requests/agent_api/registrations_test.rb`
- Create: `core_matrix/test/requests/agent_api/heartbeats_test.rb`
- Create: `core_matrix/test/requests/agent_api/health_test.rb`
- Create: `core_matrix/test/requests/agent_api/capabilities_test.rb`
- Create: `core_matrix/test/requests/agent_api/conversation_transcripts_test.rb`
- Create: `core_matrix/test/requests/agent_api/conversation_variables_test.rb`
- Create: `core_matrix/test/requests/agent_api/workspace_variables_test.rb`
- Create: `core_matrix/test/requests/agent_api/human_interactions_test.rb`
- Create: `core_matrix/test/services/agent_deployments/handshake_test.rb`
- Create: `core_matrix/test/services/agent_deployments/reconcile_config_test.rb`
- Create: `core_matrix/test/services/agent_deployments/bootstrap_test.rb`
- Create: `core_matrix/test/services/agent_deployments/rotate_machine_credential_test.rb`
- Create: `core_matrix/test/services/agent_deployments/revoke_machine_credential_test.rb`
- Create: `core_matrix/test/services/agent_deployments/retire_test.rb`
- Create: `core_matrix/test/services/agent_deployments/mark_unavailable_test.rb`
- Create: `core_matrix/test/services/agent_deployments/auto_resume_workflows_test.rb`
- Create: `core_matrix/test/services/workflows/manual_resume_test.rb`
- Create: `core_matrix/test/services/workflows/manual_retry_test.rb`
- Create: `core_matrix/test/queries/conversation_transcripts/list_query_test.rb`
- Create: `core_matrix/test/queries/conversation_variables/get_query_test.rb`
- Create: `core_matrix/test/queries/conversation_variables/mget_query_test.rb`
- Create: `core_matrix/test/queries/conversation_variables/list_query_test.rb`
- Create: `core_matrix/test/queries/conversation_variables/resolve_query_test.rb`
- Create: `core_matrix/test/queries/workspace_variables/get_query_test.rb`
- Create: `core_matrix/test/queries/workspace_variables/mget_query_test.rb`
- Create: `core_matrix/test/queries/workspace_variables/list_query_test.rb`
- Create: `core_matrix/test/integration/agent_protocol_contract_test.rb`
- Create: `core_matrix/test/integration/agent_recovery_flow_test.rb`
- Modify: `core_matrix/config/routes.rb`
- Modify: `core_matrix/app/models/agent_deployment.rb`
- Modify: `core_matrix/app/models/capability_snapshot.rb`
- Modify: `core_matrix/app/models/turn.rb`
- Modify: `core_matrix/app/models/workflow_run.rb`

**Step 1: Write failing request, service, and query tests**

Cover at least:

- machine credential authentication
- registration exchanging enrollment token for durable machine credential
- heartbeat update behavior
- health check response shape
- capabilities refresh response shape
- cursor-paginated canonical transcript listing
- conversation variable `get`, `mget`, `list`, and `resolve` behavior
- workspace variable `get`, `mget`, and `list` behavior
- variable write and promotion intent handling through machine-facing APIs
- human interaction request creation through machine-facing APIs
- handshake payload parsing and snapshot persistence
- best-effort config reconciliation across schema changes
- preserving deployment-level model slots and role-catalog references returned by capability or schema snapshots when applicable
- machine credential rotation and revocation behavior
- deployment retirement behavior
- audit rows for bootstrap, config-reconciliation fallback, credential rotation, revocation, retirement, outage-state transitions, and manual recovery
- manual resume and manual retry compatibility checks after drift, including one-time selector overrides

**Step 2: Write failing contract and integration tests**

`agent_protocol_contract_test.rb` should cover:

- registration request and response schema
- heartbeat request and response schema
- health request and response schema
- capabilities request and response schema
- transcript listing request and response schema including cursor semantics
- variable read and write request and response schema
- human interaction request schema
- handshake semantics for capability snapshots and config snapshots

`agent_recovery_flow_test.rb` should cover:

- bootstrap creating a system-owned run or workflow record
- transient outage marking work waiting
- prolonged outage pausing work
- auto-resume only when fingerprint and capabilities version did not drift
- drift requiring explicit manual resume or manual retry before work continues
- allowing one-time `role:*` or explicit-candidate overrides during manual recovery without mutating durable conversation or deployment config
- manual resume rejected when logical-agent, capability, or pinned-config compatibility checks fail
- manual retry preserving the paused run as history while starting a fresh workflow from the last stable selected input
- audit rows for bootstrap, degradation, retirement, paused-agent-unavailable transition, and explicit recovery decisions

**Step 3: Run the targeted tests to confirm failure**

Run:

```bash
cd core_matrix
bin/rails test test/requests/agent_api/registrations_test.rb test/requests/agent_api/heartbeats_test.rb test/requests/agent_api/health_test.rb test/requests/agent_api/capabilities_test.rb test/requests/agent_api/conversation_transcripts_test.rb test/requests/agent_api/conversation_variables_test.rb test/requests/agent_api/workspace_variables_test.rb test/requests/agent_api/human_interactions_test.rb test/services/agent_deployments/handshake_test.rb test/services/agent_deployments/reconcile_config_test.rb test/services/agent_deployments/bootstrap_test.rb test/services/agent_deployments/rotate_machine_credential_test.rb test/services/agent_deployments/revoke_machine_credential_test.rb test/services/agent_deployments/retire_test.rb test/services/agent_deployments/mark_unavailable_test.rb test/services/agent_deployments/auto_resume_workflows_test.rb test/services/workflows/manual_resume_test.rb test/services/workflows/manual_retry_test.rb test/queries/conversation_transcripts/list_query_test.rb test/queries/conversation_variables/get_query_test.rb test/queries/conversation_variables/mget_query_test.rb test/queries/conversation_variables/list_query_test.rb test/queries/conversation_variables/resolve_query_test.rb test/queries/workspace_variables/get_query_test.rb test/queries/workspace_variables/mget_query_test.rb test/queries/workspace_variables/list_query_test.rb test/integration/agent_protocol_contract_test.rb test/integration/agent_recovery_flow_test.rb
```

Expected:

- missing route, controller, or service failures

**Step 4: Implement minimal machine-facing boundaries**

Rules:

- no human-facing UI controllers
- machine-facing controllers should be thin wrappers around services
- transcript listing must return the canonical visible transcript only and must support cursor pagination
- variable APIs should expose explicit `get`, `mget`, `list`, and `resolve` semantics rather than ambiguous read verbs
- machine-facing variable writes and promotions remain kernel-declared intent boundaries, not direct agent-owned database writes
- machine-facing human interaction creation must create workflow-owned request resources and projection events through kernel services
- machine credential rotation must issue a fresh secret, invalidate the previous credential atomically, and create an audit row
- machine credential revocation must make the current credential unusable and create an audit row before any later re-registration
- deployment retirement must move the deployment into the `retired` state, make it ineligible for future scheduling, and create an audit row
- drift blocks silent continuation
- explicit manual resume or manual retry is required after drift before paused work can continue
- manual resume is only allowed when the replacement deployment satisfies same-logical-agent and required-capability compatibility
- manual retry must preserve the paused workflow as historical state and create a fresh execution path
- manual recovery may accept a one-time selector override, but it must not mutate the persisted conversation selector or deployment slot config
- bootstrap, config-reconciliation fallback, outage-state transitions, retirement, and manual recovery decisions must produce audit records
- agents declare intent; kernel materializes durable side effects

**Step 5: Run the targeted tests**

Run:

```bash
cd core_matrix
bin/rails test test/requests/agent_api/registrations_test.rb test/requests/agent_api/heartbeats_test.rb test/requests/agent_api/health_test.rb test/requests/agent_api/capabilities_test.rb test/requests/agent_api/conversation_transcripts_test.rb test/requests/agent_api/conversation_variables_test.rb test/requests/agent_api/workspace_variables_test.rb test/requests/agent_api/human_interactions_test.rb test/services/agent_deployments/handshake_test.rb test/services/agent_deployments/reconcile_config_test.rb test/services/agent_deployments/bootstrap_test.rb test/services/agent_deployments/rotate_machine_credential_test.rb test/services/agent_deployments/revoke_machine_credential_test.rb test/services/agent_deployments/retire_test.rb test/services/agent_deployments/mark_unavailable_test.rb test/services/agent_deployments/auto_resume_workflows_test.rb test/services/workflows/manual_resume_test.rb test/services/workflows/manual_retry_test.rb test/queries/conversation_transcripts/list_query_test.rb test/queries/conversation_variables/get_query_test.rb test/queries/conversation_variables/mget_query_test.rb test/queries/conversation_variables/list_query_test.rb test/queries/conversation_variables/resolve_query_test.rb test/queries/workspace_variables/get_query_test.rb test/queries/workspace_variables/mget_query_test.rb test/queries/workspace_variables/list_query_test.rb test/integration/agent_protocol_contract_test.rb test/integration/agent_recovery_flow_test.rb
```

Expected:

- targeted tests pass

**Step 6: Commit**

```bash
git -C .. add core_matrix/app/controllers/agent_api core_matrix/config/routes.rb core_matrix/app/models core_matrix/app/services/agent_deployments core_matrix/app/services/workflows core_matrix/app/queries/conversation_transcripts core_matrix/app/queries/conversation_variables core_matrix/app/queries/workspace_variables core_matrix/script/manual/dummy_agent_runtime.rb core_matrix/test/requests core_matrix/test/services core_matrix/test/queries core_matrix/test/integration
git -C .. commit -m "feat: add agent protocol boundaries and recovery flows"
```

### Task 12: Add Publication, Query Objects, Seeds, Checklist Updates, And Final Verification

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

Those belong to `docs/plans/2026-03-24-core-matrix-kernel-ui-follow-up.md`.
