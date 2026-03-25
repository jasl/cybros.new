# Core Matrix Phase 1 Identifier Policy Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add durable `public_id` support to the approved `core_matrix`
resource set while keeping internal `bigint` primary keys and making PostgreSQL
18 an explicit, testable baseline.

**Architecture:** Keep the relational substrate and foreign-key graph on
`bigint`, and add `public_id :uuid` only to resources that cross public or
durable operator-facing boundaries. Generate those identifiers in PostgreSQL
with `uuidv7()`, route public lookups through `public_id`, leave framework
tables alone, and document the rule so future features do not leak internal
IDs.

**Tech Stack:** Ruby on Rails, Active Record, PostgreSQL 18, Minitest, GitHub
Actions, Brakeman, Bundler Audit, RuboCop, Bun

---

### Task 1: Pin PostgreSQL 18 In CI

**Files:**
- Modify: `.github/workflows/ci.yml`

**Step 1: Confirm the current CI service image is floating**

Open the `core_matrix` jobs in `.github/workflows/ci.yml` and confirm both test
jobs still use the floating `postgres` image. Treat that as the failing
baseline because the identifier policy requires an explicit PostgreSQL 18
contract.

**Step 2: Pin the CI service image**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
rg -n "image: postgres" .github/workflows/ci.yml
```

Expected:

- the workflow shows the floating image entries that need pinning

Change the `core_matrix` GitHub Actions PostgreSQL services from `postgres` to
`postgres:18`.

**Step 3: Re-run the workflow grep to verify the pin**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
rg -n "image: postgres(:18)?$" .github/workflows/ci.yml
```

Expected:

- the `core_matrix` jobs now point at `postgres:18`

**Step 4: Let later migration-backed test tasks prove runtime support**

Do not add a dedicated database-baseline test. If `uuidv7()` support or the
PostgreSQL 18 contract is missing, the first migration reset and subsequent
`db:test:prepare` steps in later tasks will fail immediately.

**Step 5: Commit**

```bash
git -C .. add .github/workflows/ci.yml
git -C .. commit -m "chore: pin core matrix to postgres 18"
```

### Task 2: Add A Reusable Public Identifier Model Concern

**Files:**
- Create: `core_matrix/app/models/concerns/has_public_id.rb`
- Create: `core_matrix/test/models/concerns/has_public_id_test.rb`

**Step 1: Write the failing concern test**

Create a small concern test that builds a temporary test table and a test-only
model including `HasPublicId`, then proves the database default populates
`public_id` and the concern exposes a common lookup helper:

```ruby
ActiveRecord::Base.with_connection do |connection|
  connection.create_table :public_id_concern_test_records, force: true do |t|
    t.uuid :public_id, null: false, default: -> { "uuidv7()" }
  end
  connection.add_index :public_id_concern_test_records, :public_id, unique: true
end

class PublicIdConcernTestRecord < ApplicationRecord
  self.table_name = "public_id_concern_test_records"
  include HasPublicId
end

record = PublicIdConcernTestRecord.create!

assert record.public_id.present?
assert_equal record, PublicIdConcernTestRecord.find_by_public_id!(record.public_id)
```

**Step 2: Run the concern test to verify failure**

Run:

```bash
cd core_matrix
bin/rails test test/models/concerns/has_public_id_test.rb
```

Expected:

- the test fails because the concern and shared lookup helper do not exist yet

**Step 3: Implement the minimal concern**

Add a concern that:

- relies on the database to populate and enforce non-null `public_id`
- defines uniqueness validation for persisted application-level safety
- defines `find_by_public_id!`
- does not override or obscure internal `id`

Keep the concern small and reusable so models can opt in explicitly.

**Step 4: Run the concern test to verify it passes**

Run:

```bash
cd core_matrix
bin/rails test test/models/concerns/has_public_id_test.rb
```

Expected:

- the concern test passes

**Step 5: Commit**

```bash
git -C .. add core_matrix/app/models/concerns/has_public_id.rb core_matrix/test/models/concerns/has_public_id_test.rb
git -C .. commit -m "feat: add shared public id concern"
```

### Task 3: Add Public IDs To Identity And Workspace Roots

**Files:**
- Modify: `core_matrix/db/migrate/20260324090002_create_users.rb`
- Modify: `core_matrix/db/migrate/20260324090003_create_invitations.rb`
- Modify: `core_matrix/db/migrate/20260324090004_create_sessions.rb`
- Modify: `core_matrix/db/migrate/20260324090012_create_workspaces.rb`
- Modify: `core_matrix/app/models/user.rb`
- Modify: `core_matrix/app/models/invitation.rb`
- Modify: `core_matrix/app/models/session.rb`
- Modify: `core_matrix/app/models/workspace.rb`
- Modify: `core_matrix/test/models/user_test.rb`
- Modify: `core_matrix/test/models/invitation_test.rb`
- Modify: `core_matrix/test/models/session_test.rb`
- Modify: `core_matrix/test/models/workspace_test.rb`

**Step 1: Write the failing model tests**

Add assertions that each approved root now generates a `public_id` and can be
resolved by it:

```ruby
user = create_user!(role: "admin")

assert user.public_id.present?
assert_equal user, User.find_by_public_id!(user.public_id)
```

Repeat the pattern for `Invitation`, `Session`, and `Workspace`.

**Step 2: Run the targeted tests to verify failure**

Run:

```bash
cd core_matrix
bin/rails test test/models/user_test.rb test/models/invitation_test.rb test/models/session_test.rb test/models/workspace_test.rb
```

Expected:

- the tests fail because the schema and models do not expose `public_id`

**Step 3: Implement the minimal schema and model changes**

Edit the Phase 1 create-table migrations to add:

- `t.uuid :public_id, null: false, default: -> { "uuidv7()" }`
- a unique index on `public_id`

Include `HasPublicId` in the four models.

**Step 4: Reset the databases and run the targeted tests**

Run:

```bash
cd core_matrix
bin/rails db:drop db:create db:migrate
bin/rails db:test:prepare
bin/rails test test/models/user_test.rb test/models/invitation_test.rb test/models/session_test.rb test/models/workspace_test.rb
```

Expected:

- the migrations load cleanly after reset
- the four model suites pass with generated `public_id` values

**Step 5: Commit**

```bash
git -C .. add core_matrix/db/migrate/20260324090002_create_users.rb core_matrix/db/migrate/20260324090003_create_invitations.rb core_matrix/db/migrate/20260324090004_create_sessions.rb core_matrix/db/migrate/20260324090012_create_workspaces.rb core_matrix/app/models/user.rb core_matrix/app/models/invitation.rb core_matrix/app/models/session.rb core_matrix/app/models/workspace.rb core_matrix/test/models/user_test.rb core_matrix/test/models/invitation_test.rb core_matrix/test/models/session_test.rb core_matrix/test/models/workspace_test.rb core_matrix/db/schema.rb
git -C .. commit -m "feat: add public ids to identity roots"
```

### Task 4: Add Public IDs To Agent Registry And Execution Environment Resources

**Files:**
- Modify: `core_matrix/db/migrate/20260324090006_create_agent_installations.rb`
- Modify: `core_matrix/db/migrate/20260324090007_create_execution_environments.rb`
- Modify: `core_matrix/db/migrate/20260324090009_create_agent_deployments.rb`
- Modify: `core_matrix/app/models/agent_installation.rb`
- Modify: `core_matrix/app/models/execution_environment.rb`
- Modify: `core_matrix/app/models/agent_deployment.rb`
- Modify: `core_matrix/test/models/agent_installation_test.rb`
- Modify: `core_matrix/test/models/execution_environment_test.rb`
- Modify: `core_matrix/test/models/agent_deployment_test.rb`

**Step 1: Write the failing agent identifier tests**

Add tests that assert the registry resources generate `public_id` values and can
be looked up through the shared concern:

```ruby
installation = create_installation!
deployment = create_agent_deployment!(installation: installation)

assert deployment.public_id.present?
assert_equal deployment, AgentDeployment.find_by_public_id!(deployment.public_id)
```

Repeat the pattern for `AgentInstallation` and `ExecutionEnvironment`.

**Step 2: Run the targeted tests to verify failure**

Run:

```bash
cd core_matrix
bin/rails test test/models/agent_installation_test.rb test/models/execution_environment_test.rb test/models/agent_deployment_test.rb
```

Expected:

- the tests fail because the new columns and concern wiring do not exist yet

**Step 3: Implement the minimal schema and model changes**

Add `public_id` with `uuidv7()` defaults and unique indexes in the original
create-table migrations, then include `HasPublicId` in all three models.

**Step 4: Reset the databases and run the targeted tests**

Run:

```bash
cd core_matrix
bin/rails db:drop db:create db:migrate
bin/rails db:test:prepare
bin/rails test test/models/agent_installation_test.rb test/models/execution_environment_test.rb test/models/agent_deployment_test.rb
```

Expected:

- both model suites pass with generated public identifiers

**Step 5: Commit**

```bash
git -C .. add core_matrix/db/migrate/20260324090006_create_agent_installations.rb core_matrix/db/migrate/20260324090007_create_execution_environments.rb core_matrix/db/migrate/20260324090009_create_agent_deployments.rb core_matrix/app/models/agent_installation.rb core_matrix/app/models/execution_environment.rb core_matrix/app/models/agent_deployment.rb core_matrix/test/models/agent_installation_test.rb core_matrix/test/models/execution_environment_test.rb core_matrix/test/models/agent_deployment_test.rb core_matrix/db/schema.rb
git -C .. commit -m "feat: add public ids to agent registry resources"
```

### Task 5: Add Public IDs To Conversation And Messaging Resources

**Files:**
- Modify: `core_matrix/db/migrate/20260324090019_create_conversations.rb`
- Modify: `core_matrix/db/migrate/20260324090021_create_turns.rb`
- Modify: `core_matrix/db/migrate/20260324090022_create_messages.rb`
- Modify: `core_matrix/db/migrate/20260324090025_create_message_attachments.rb`
- Modify: `core_matrix/app/models/conversation.rb`
- Modify: `core_matrix/app/models/turn.rb`
- Modify: `core_matrix/app/models/message.rb`
- Modify: `core_matrix/app/models/message_attachment.rb`
- Modify: `core_matrix/test/models/conversation_test.rb`
- Modify: `core_matrix/test/models/turn_test.rb`
- Modify: `core_matrix/test/models/message_test.rb`
- Modify: `core_matrix/test/models/message_attachment_test.rb`

**Step 1: Write the failing conversation-domain tests**

Add tests for each approved resource that assert:

- `public_id` is generated on create
- the shared lookup helper resolves the record
- existing ordering behavior still uses explicit fields rather than
  `public_id`

Example:

```ruby
context = create_workspace_context!
conversation = Conversations::CreateRoot.call(workspace: context[:workspace])
first_turn = Turns::StartUserTurn.call(
  conversation: conversation,
  content: "First",
  agent_deployment: context[:agent_deployment],
  resolved_config_snapshot: {},
  resolved_model_selection_snapshot: {}
)
second_turn = Turns::StartUserTurn.call(
  conversation: conversation,
  content: "Second",
  agent_deployment: context[:agent_deployment],
  resolved_config_snapshot: {},
  resolved_model_selection_snapshot: {}
)

assert conversation.public_id.present?
assert_equal conversation, Conversation.find_by_public_id!(conversation.public_id)
assert_equal [first_turn.id, second_turn.id], conversation.turns.order(:sequence).pluck(:id)
```

**Step 2: Run the targeted tests to verify failure**

Run:

```bash
cd core_matrix
bin/rails test test/models/conversation_test.rb test/models/turn_test.rb test/models/message_test.rb test/models/message_attachment_test.rb
```

Expected:

- the tests fail because the schema does not yet provide `public_id`

**Step 3: Implement the minimal schema and model changes**

Add `public_id` columns, unique indexes, and `HasPublicId` inclusion to the
approved conversation-domain models only.

**Step 4: Reset the databases and run the targeted tests**

Run:

```bash
cd core_matrix
bin/rails db:drop db:create db:migrate
bin/rails db:test:prepare
bin/rails test test/models/conversation_test.rb test/models/turn_test.rb test/models/message_test.rb test/models/message_attachment_test.rb
```

Expected:

- the conversation and messaging model suites pass
- existing sequence- and timestamp-based ordering assertions still hold

**Step 5: Commit**

```bash
git -C .. add core_matrix/db/migrate/20260324090019_create_conversations.rb core_matrix/db/migrate/20260324090021_create_turns.rb core_matrix/db/migrate/20260324090022_create_messages.rb core_matrix/db/migrate/20260324090025_create_message_attachments.rb core_matrix/app/models/conversation.rb core_matrix/app/models/turn.rb core_matrix/app/models/message.rb core_matrix/app/models/message_attachment.rb core_matrix/test/models/conversation_test.rb core_matrix/test/models/turn_test.rb core_matrix/test/models/message_test.rb core_matrix/test/models/message_attachment_test.rb core_matrix/db/schema.rb
git -C .. commit -m "feat: add public ids to conversation resources"
```

### Task 6: Add Public IDs To Runtime Workflow And Publication Resources

**Files:**
- Modify: `core_matrix/db/migrate/20260324090035_create_human_interaction_requests.rb`
- Modify: `core_matrix/db/migrate/20260324090028_create_workflow_runs.rb`
- Modify: `core_matrix/db/migrate/20260324090029_create_workflow_nodes.rb`
- Modify: `core_matrix/db/migrate/20260324090040_create_publications.rb`
- Modify: `core_matrix/app/models/human_interaction_request.rb`
- Modify: `core_matrix/app/models/workflow_run.rb`
- Modify: `core_matrix/app/models/workflow_node.rb`
- Modify: `core_matrix/app/models/publication.rb`
- Modify: `core_matrix/test/models/human_interaction_request_test.rb`
- Modify: `core_matrix/test/models/workflow_run_test.rb`
- Modify: `core_matrix/test/models/workflow_node_test.rb`
- Modify: `core_matrix/test/models/publication_test.rb`

**Step 1: Write the failing runtime and publication tests**

Add the same `public_id` generation and lookup coverage for:

- `HumanInteractionRequest`
- `WorkflowRun`
- `WorkflowNode`
- `Publication`

**Step 2: Run the targeted tests to verify failure**

Run:

```bash
cd core_matrix
bin/rails test test/models/human_interaction_request_test.rb test/models/workflow_run_test.rb test/models/workflow_node_test.rb test/models/publication_test.rb
```

Expected:

- the tests fail until the schema and models adopt `public_id`

**Step 3: Implement the minimal schema and model changes**

Add the `public_id` columns and indexes in the original migrations and include
`HasPublicId` in the four models.

**Step 4: Reset the databases and run the targeted tests**

Run:

```bash
cd core_matrix
bin/rails db:drop db:create db:migrate
bin/rails db:test:prepare
bin/rails test test/models/human_interaction_request_test.rb test/models/workflow_run_test.rb test/models/workflow_node_test.rb test/models/publication_test.rb
```

Expected:

- the three model suites pass with generated public identifiers

**Step 5: Commit**

```bash
git -C .. add core_matrix/db/migrate/20260324090035_create_human_interaction_requests.rb core_matrix/db/migrate/20260324090028_create_workflow_runs.rb core_matrix/db/migrate/20260324090029_create_workflow_nodes.rb core_matrix/db/migrate/20260324090040_create_publications.rb core_matrix/app/models/human_interaction_request.rb core_matrix/app/models/workflow_run.rb core_matrix/app/models/workflow_node.rb core_matrix/app/models/publication.rb core_matrix/test/models/human_interaction_request_test.rb core_matrix/test/models/workflow_run_test.rb core_matrix/test/models/workflow_node_test.rb core_matrix/test/models/publication_test.rb core_matrix/db/schema.rb
git -C .. commit -m "feat: add public ids to runtime resources"
```

### Task 7: Move Public Boundaries To Public ID Lookups

**Files:**
- Modify: `core_matrix/app/controllers/agent_api/base_controller.rb`
- Modify: `core_matrix/app/controllers/agent_api/conversation_transcripts_controller.rb`
- Modify: `core_matrix/app/controllers/agent_api/conversation_variables_controller.rb`
- Modify: `core_matrix/app/controllers/agent_api/workspace_variables_controller.rb`
- Modify: `core_matrix/app/controllers/agent_api/human_interactions_controller.rb`
- Modify: `core_matrix/app/controllers/agent_api/registrations_controller.rb`
- Modify: `core_matrix/app/controllers/agent_api/health_controller.rb`
- Modify: `core_matrix/app/controllers/agent_api/heartbeats_controller.rb`
- Modify: `core_matrix/app/services/agent_deployments/register.rb`
- Modify: `core_matrix/app/services/agent_deployments/bootstrap.rb`
- Modify: `core_matrix/app/services/turns/start_user_turn.rb`
- Modify: `core_matrix/app/services/turns/queue_follow_up.rb`
- Modify: `core_matrix/app/services/workflows/context_assembler.rb`
- Modify: `core_matrix/app/queries/conversation_transcripts/list_query.rb`
- Modify: `core_matrix/test/requests/agent_api/conversation_transcripts_test.rb`
- Modify: `core_matrix/test/requests/agent_api/conversation_variables_test.rb`
- Modify: `core_matrix/test/requests/agent_api/workspace_variables_test.rb`
- Modify: `core_matrix/test/requests/agent_api/human_interactions_test.rb`
- Modify: `core_matrix/test/requests/agent_api/registrations_test.rb`
- Modify: `core_matrix/test/requests/agent_api/health_test.rb`
- Modify: `core_matrix/test/requests/agent_api/heartbeats_test.rb`
- Modify: `core_matrix/test/services/turns/start_user_turn_test.rb`
- Modify: `core_matrix/test/services/turns/queue_follow_up_test.rb`
- Modify: `core_matrix/test/services/agent_deployments/bootstrap_test.rb`
- Modify: `core_matrix/test/services/workflows/context_assembler_test.rb`
- Modify: `core_matrix/test/integration/agent_runtime_resource_api_test.rb`
- Modify: `core_matrix/test/integration/agent_registration_contract_test.rb`
- Modify: `core_matrix/test/integration/canonical_variable_flow_test.rb`
- Modify: `core_matrix/test/integration/human_interaction_flow_test.rb`

**Step 1: Write the failing request and integration coverage**

For each existing public or operator-facing surface that exposes a resource
identifier, add or update coverage so it:

- looks up the resource by `public_id`
- keeps contract field names stable where appropriate, even if a field such as
  `conversation_id` now carries a UUID public identifier
- does not serialize raw internal `id`
- does not expose raw canonical-variable row IDs after `canonical_variables`
  stay out of scope for `public_id`

Representative expectation:

```ruby
assert_equal conversation.public_id, response.parsed_body.fetch("conversation_id")
refute_includes response.body, %("#{conversation.id}")
```

**Step 2: Run the targeted request and integration tests to verify failure**

Run:

```bash
cd core_matrix
bin/rails test test/requests/agent_api/conversation_transcripts_test.rb test/requests/agent_api/conversation_variables_test.rb test/requests/agent_api/workspace_variables_test.rb test/requests/agent_api/human_interactions_test.rb test/requests/agent_api/registrations_test.rb test/requests/agent_api/health_test.rb test/requests/agent_api/heartbeats_test.rb test/integration/agent_runtime_resource_api_test.rb test/integration/agent_registration_contract_test.rb test/integration/canonical_variable_flow_test.rb test/integration/human_interaction_flow_test.rb
```

Expected:

- affected tests fail anywhere a public response still leaks internal IDs or
  lookup semantics

**Step 3: Implement the minimal lookup and serialization changes**

Update controllers, queries, and serializers so:

- external lookups use `find_by_public_id!`
- public payloads emit `public_id`
- field names may remain `*_id` where the protocol already depends on them
- internal service wiring stays on `bigint` after the boundary lookup
- runtime payload helpers and turn-origin source references also emit
  `public_id` whenever they point at an in-scope external resource
- canonical-variable payloads stop exposing raw variable row IDs because
  `canonical_variables` are out of scope for `public_id`

Do not add mixed fallback logic that accepts raw `id`.

**Step 4: Run the targeted request and integration tests to verify they pass**

Run:

```bash
cd core_matrix
bin/rails test test/requests/agent_api/conversation_transcripts_test.rb test/requests/agent_api/conversation_variables_test.rb test/requests/agent_api/workspace_variables_test.rb test/requests/agent_api/human_interactions_test.rb test/requests/agent_api/registrations_test.rb test/requests/agent_api/health_test.rb test/requests/agent_api/heartbeats_test.rb test/integration/agent_runtime_resource_api_test.rb test/integration/agent_registration_contract_test.rb test/integration/canonical_variable_flow_test.rb test/integration/human_interaction_flow_test.rb
```

Expected:

- the public boundary tests pass without raw internal IDs leaking

**Step 5: Commit**

```bash
git -C .. add core_matrix/app/controllers/agent_api/base_controller.rb core_matrix/app/controllers/agent_api/conversation_transcripts_controller.rb core_matrix/app/controllers/agent_api/conversation_variables_controller.rb core_matrix/app/controllers/agent_api/workspace_variables_controller.rb core_matrix/app/controllers/agent_api/human_interactions_controller.rb core_matrix/app/controllers/agent_api/registrations_controller.rb core_matrix/app/controllers/agent_api/health_controller.rb core_matrix/app/controllers/agent_api/heartbeats_controller.rb core_matrix/app/queries/conversation_transcripts/list_query.rb core_matrix/test/requests/agent_api/conversation_transcripts_test.rb core_matrix/test/requests/agent_api/conversation_variables_test.rb core_matrix/test/requests/agent_api/workspace_variables_test.rb core_matrix/test/requests/agent_api/human_interactions_test.rb core_matrix/test/requests/agent_api/registrations_test.rb core_matrix/test/requests/agent_api/health_test.rb core_matrix/test/requests/agent_api/heartbeats_test.rb core_matrix/test/integration/agent_runtime_resource_api_test.rb core_matrix/test/integration/agent_registration_contract_test.rb core_matrix/test/integration/canonical_variable_flow_test.rb core_matrix/test/integration/human_interaction_flow_test.rb
git -C .. commit -m "feat: expose public ids at resource boundaries"
```

### Task 8: Record The Policy In Behavior Docs And AGENTS Guidance

**Files:**
- Create: `core_matrix/docs/behavior/identifier-policy.md`
- Modify: `core_matrix/docs/behavior/agent-registration-and-capability-handshake.md`
- Modify: `core_matrix/docs/behavior/agent-runtime-resource-apis.md`
- Modify: `core_matrix/docs/behavior/workflow-context-assembly-and-execution-snapshot.md`
- Modify: `core_matrix/docs/behavior/turn-entry-and-selector-state.md`
- Modify: `core_matrix/docs/behavior/deployment-bootstrap-and-recovery-flows.md`
- Modify: `AGENTS.md`
- Modify: `docs/plans/README.md`

**Step 1: Write the failing documentation checklist**

Create a short checklist in the new behavior doc describing the expected
coverage:

- approved in-scope resources
- external lookup rule
- ordering rule
- explicit exclusions
- PostgreSQL 18 baseline

Treat the task as failing until each item is covered in prose.

**Step 2: Review the docs against the approved design**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
rg -n "public_id|uuidv7|PostgreSQL 18|external lookup|ordering" docs/finished-plans/2026-03-25-core-matrix-phase-1-identifier-policy-design.md core_matrix/docs/behavior/identifier-policy.md AGENTS.md
```

Expected:

- each approved rule appears in the behavior doc
- `AGENTS.md` contains only a concise cross-reference, not the full product policy

**Step 3: Implement the documentation updates**

Add a behavior document that becomes the product-level source of truth and keep
the root `AGENTS.md` change short and scoped.

**Step 4: Re-run the documentation review**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
rg -n "public_id|uuidv7|PostgreSQL 18|external lookup|ordering" docs/finished-plans/2026-03-25-core-matrix-phase-1-identifier-policy-design.md core_matrix/docs/behavior/identifier-policy.md AGENTS.md
```

Expected:

- the policy is present in the behavior docs and discoverable from `AGENTS.md`

**Step 5: Commit**

```bash
git -C .. add core_matrix/docs/behavior/identifier-policy.md AGENTS.md docs/plans/README.md
git -C .. commit -m "docs: record core matrix identifier policy"
```

### Task 9: Run The Full Core Matrix Verification Suite

**Files:**
- Modify: `docs/finished-plans/2026-03-25-core-matrix-phase-1-identifier-policy-implementation-plan.md`

**Step 1: Run targeted regression suites first**

Run:

```bash
cd core_matrix
bin/rails test test/models test/requests test/integration
```

Expected:

- the resource-model and boundary tests pass before the full suite

**Step 2: Run the standard verification commands**

Run:

```bash
cd core_matrix
bin/brakeman --no-pager
bin/bundler-audit
bin/rubocop -f github
bun run lint:js
bin/rails db:test:prepare test
bin/rails db:test:prepare test:system
```

Expected:

- all standard `core_matrix` verification commands pass on the PostgreSQL 18
  baseline

**Step 3: Record the verification evidence in the plan**

Update the plan file with a short completion note listing the exact commands
that passed and any caveats discovered during the run.

Completion note to record after verification:

- public boundary lookups reject raw bigint IDs instead of accepting fallback
  resolution
- `turn_origin.source_ref_id` now carries `public_id` for in-scope resources
- registration treats foreign execution environments as controlled
  unprocessable-entity errors

**Step 4: Re-open the design and behavior docs for a final review**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
sed -n '1,240p' docs/finished-plans/2026-03-25-core-matrix-phase-1-identifier-policy-design.md
sed -n '1,240p' core_matrix/docs/behavior/identifier-policy.md
```

Expected:

- the final docs still match the shipped behavior and approved scope

**Step 5: Commit**

```bash
git -C .. add docs/finished-plans/2026-03-25-core-matrix-phase-1-identifier-policy-implementation-plan.md
git -C .. commit -m "test: verify core matrix identifier policy rollout"
```

### Verification Note (2026-03-25)

The post-rollout review found and corrected three gaps after the original
execution pass:

- `turn_origin.source_ref_id` still leaked internal bigint IDs for manual-user
  and deployment-bootstrap turns, so the turn producers now persist
  `User.public_id` and `AgentDeployment.public_id` instead
- registration now maps cross-installation execution-environment mismatches to
  a controlled `422 unprocessable_entity` error through
  `AgentDeployments::Register::ExecutionEnvironmentMismatch`
- request coverage now proves raw bigint identifiers are rejected at the
  machine-facing boundary instead of being accepted as fallback lookups

Fresh verification completed with these exact commands:

```bash
cd core_matrix
bin/rails test test/models/concerns/has_public_id_test.rb test/requests/agent_api/registrations_test.rb test/requests/agent_api/conversation_variables_test.rb test/requests/agent_api/human_interactions_test.rb test/services/turns/start_user_turn_test.rb test/services/turns/queue_follow_up_test.rb test/services/agent_deployments/bootstrap_test.rb test/services/workflows/context_assembler_test.rb
bin/rails test test/requests/agent_api/workspace_variables_test.rb test/requests/agent_api/conversation_transcripts_test.rb
bin/brakeman --no-pager
bin/bundler-audit
bin/rubocop -f github
bun run lint:js
bin/rails db:test:prepare test
bin/rails db:test:prepare test:system
```

Observed result:

- every command above passed on the PostgreSQL 18 baseline
- `bin/rails db:test:prepare test:system` still runs `0` system tests in the
  current tree; this is an existing coverage gap, not a regression introduced
  by the identifier-policy rollout
