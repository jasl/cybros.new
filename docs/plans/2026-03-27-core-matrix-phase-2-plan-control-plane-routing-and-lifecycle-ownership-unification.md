# Core Matrix Phase 2 Control-Plane Routing And Lifecycle Ownership Unification Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Collapse mailbox routing, runtime-plane targeting, and control-report lifecycle handling onto one explicit control-plane contract so `AgentControl::Report` stops being a convention-heavy multi-role sink.

**Architecture:** Promote mailbox routing semantics out of JSON payload inference into durable mailbox columns, route poll/publish/report through one shared routing contract, split control-report handling into family-specific handlers behind a thin idempotent ingress shell, and keep lifecycle ownership explicit for execution and close reports.

**Tech Stack:** Ruby on Rails (`core_matrix`), Active Record, direct migration edits during Phase 2 acceptance, Minitest model/service/request/e2e coverage, mailbox routing indexes, behavior docs

---

## Execution Rules

- Treat this as a breaking cleanup for the current Phase 2 control plane.
- Do not keep payload-based runtime-plane inference or SQL routing by JSON
  payload once this batch lands.
- Do not keep `AgentControl::Report` as the direct owner of every report-family
  branch and every stale-check variant.
- The durable mailbox row must explicitly own routing semantics:
  - runtime plane
  - durable target reference
  - optional target execution environment
- Family-specific lifecycle behavior must live in dedicated handlers, not in a
  single growable intake class.
- Keep one ingress shell for:
  - activity touch
  - duplicate detection
  - receipt creation
  - stale-to-HTTP translation
- Because compatibility is intentionally out of scope, it is acceptable to:
  - edit the original Phase 2 mailbox migration directly
  - rebuild `db/schema.rb`
  - reset the development and test databases
- Final verification is not complete until grep confirms:
  - no `inferred_runtime_plane` remains
  - no SQL routing branch still reads `payload ->> 'runtime_plane'`
  - `AgentControl::Report` no longer contains per-family execution and close
    lifecycle bodies
- Commit after every task with the suggested message or a tighter equivalent.

## Target Shape

After this batch:

- `agent_control_mailbox_items` stores routing semantics in first-class columns:
  - `runtime_plane`
  - `target_execution_environment_id` when the row is environment-plane
- mailbox payload remains for family-specific request data, not for routing
  identity.
- `AgentControlMailboxItem#runtime_plane` reads the durable column directly.
- `ResolveTargetRuntime`, `Poll`, `PublishPending`, mailbox writers, and
  report handlers all use the same routing contract.
- `AgentControl::Report` becomes a thin ingress shell that delegates to:
  - execution report handler
  - close report handler
  - deployment health report handler
- stale validation for execution reports and close reports is handled by shared
  family-specific validators, not by one growing file.
- environment-plane targeting is explicit at write time and validated against
  a real execution environment foreign key.

## Current Implementations That Must Be Adjusted

- `core_matrix/db/migrate/20260326113000_add_agent_control_contract_for_phase_two.rb`
  Reason: mailbox routing semantics currently live partly in payload JSON.
- `core_matrix/db/schema.rb`
  Reason: must be regenerated after the migration edit.
- `core_matrix/app/models/agent_control_mailbox_item.rb`
  Reason: still infers runtime plane and mixes routing validation with payload
  conventions.
- `core_matrix/app/services/agent_control/create_execution_assignment.rb`
  Reason: mailbox writers must populate the explicit routing columns.
- `core_matrix/app/services/agent_control/create_resource_close_request.rb`
  Reason: currently writes environment-plane targeting only into payload and
  target_ref.
- `core_matrix/app/services/agent_control/serialize_mailbox_item.rb`
  Reason: must serialize the first-class routing contract from durable fields.
- `core_matrix/app/services/agent_control/resolve_target_runtime.rb`
  Reason: should become the single routing owner for poll/publish/report.
- `core_matrix/app/services/agent_control/poll.rb`
  Reason: currently queries environment-plane work from JSON payload fields.
- `core_matrix/app/services/agent_control/publish_pending.rb`
  Reason: should route through the shared contract with no payload fallback.
- `core_matrix/app/services/agent_control/report.rb`
  Reason: currently combines ingress shell, execution lifecycle handling, close
  lifecycle handling, and health handling.
- `core_matrix/docs/behavior/agent-runtime-resource-apis.md`
  Reason: currently documents explicit runtime plane conceptually, but the row
  semantics still drift partly through payload.
- `core_matrix/docs/behavior/workflow-scheduler-and-wait-states.md`
  Reason: close-request delivery rules should reflect the new explicit routing
  owner.
- `docs/reports/core-matrix-architecture-health-audit-register.md`
  Reason: should mark the control-plane unification opportunity as implemented
  once complete.
- `docs/reports/2026-03-27-core-matrix-architecture-health-audit-round-1.md`
  Reason: should be updated with an implementation note after landing.

## Anticipated File Set

### Create

- `core_matrix/app/services/agent_control/report_dispatch.rb`
- `core_matrix/app/services/agent_control/handle_execution_report.rb`
- `core_matrix/app/services/agent_control/handle_close_report.rb`
- `core_matrix/app/services/agent_control/handle_health_report.rb`
- `core_matrix/app/services/agent_control/validate_execution_report_freshness.rb`
- `core_matrix/app/services/agent_control/validate_close_report_freshness.rb`
- `core_matrix/test/services/agent_control/publish_pending_test.rb`

### Modify

- `core_matrix/db/migrate/20260326113000_add_agent_control_contract_for_phase_two.rb`
- `core_matrix/db/schema.rb`
- `core_matrix/app/models/agent_control_mailbox_item.rb`
- `core_matrix/app/services/agent_control/create_execution_assignment.rb`
- `core_matrix/app/services/agent_control/create_resource_close_request.rb`
- `core_matrix/app/services/agent_control/serialize_mailbox_item.rb`
- `core_matrix/app/services/agent_control/resolve_target_runtime.rb`
- `core_matrix/app/services/agent_control/poll.rb`
- `core_matrix/app/services/agent_control/publish_pending.rb`
- `core_matrix/app/services/agent_control/report.rb`
- `core_matrix/test/models/agent_control_mailbox_item_test.rb`
- `core_matrix/test/services/agent_control/poll_test.rb`
- `core_matrix/test/services/agent_control/report_test.rb`
- `core_matrix/test/requests/agent_api/control_poll_test.rb`
- `core_matrix/test/requests/agent_api/resource_close_test.rb`
- `core_matrix/test/requests/agent_api/execution_delivery_test.rb`
- `core_matrix/test/e2e/protocol/turn_interrupt_e2e_test.rb`
- `core_matrix/test/e2e/protocol/conversation_close_e2e_test.rb`
- `core_matrix/test/e2e/protocol/process_close_escalation_e2e_test.rb`
- `core_matrix/test/test_helper.rb`
- `core_matrix/docs/behavior/agent-runtime-resource-apis.md`
- `core_matrix/docs/behavior/workflow-scheduler-and-wait-states.md`
- `docs/reports/core-matrix-architecture-health-audit-register.md`
- `docs/reports/2026-03-27-core-matrix-architecture-health-audit-round-1.md`

## Task 1: Promote Mailbox Routing Semantics Into Durable Columns

**Files:**

- Modify: `core_matrix/db/migrate/20260326113000_add_agent_control_contract_for_phase_two.rb`
- Modify: `core_matrix/db/schema.rb`
- Modify: `core_matrix/app/models/agent_control_mailbox_item.rb`
- Modify: `core_matrix/app/services/agent_control/create_execution_assignment.rb`
- Modify: `core_matrix/app/services/agent_control/create_resource_close_request.rb`
- Modify: `core_matrix/app/services/agent_control/serialize_mailbox_item.rb`
- Modify: `core_matrix/test/models/agent_control_mailbox_item_test.rb`
- Modify: `core_matrix/test/requests/agent_api/control_poll_test.rb`
- Modify: `core_matrix/test/test_helper.rb`

**Step 1: Write the failing tests**

Add tests proving:

- mailbox items persist `runtime_plane` in a first-class column
- environment-plane rows persist `target_execution_environment_id` directly
- `AgentControlMailboxItem` no longer accepts omitted runtime plane by
  inference
- serialized mailbox envelopes still expose the same wire fields, but source
  them from durable columns rather than payload fallback

Example expectation:

```ruby
assert_equal "environment", mailbox_item.runtime_plane
assert_equal context[:execution_environment].id, mailbox_item.target_execution_environment_id
assert_equal context[:execution_environment].public_id, mailbox_item.target_ref
```

**Step 2: Run tests to verify they fail**

Run:

```bash
cd core_matrix
bin/rails test \
  test/models/agent_control_mailbox_item_test.rb \
  test/requests/agent_api/control_poll_test.rb
```

Expected: FAIL because the durable routing columns do not yet exist.

**Step 3: Write the minimal implementation**

Implement the breaking schema change:

- edit `20260326113000_add_agent_control_contract_for_phase_two.rb` to add:
  - `runtime_plane :string, null: false`
  - `target_execution_environment` reference, optional but installation-scoped
- add indexes that support:
  - agent-installation delivery
  - agent-deployment delivery
  - environment-plane delivery by execution environment and status
- update mailbox writers to populate the new routing columns
- update `test/test_helper.rb` mailbox builders so test fixtures create valid
  rows under the new durable routing contract
- remove `inferred_runtime_plane`
- keep payload for family-specific request metadata only

**Step 4: Reset schema and databases**

Run:

```bash
cd core_matrix
bin/rails db:drop db:create db:schema:load
RAILS_ENV=test bin/rails db:drop db:create db:schema:load
```

**Step 5: Run tests to verify they pass**

Run the same targeted test command and confirm PASS.

**Step 6: Commit**

```bash
git add core_matrix/db/migrate/20260326113000_add_agent_control_contract_for_phase_two.rb \
  core_matrix/db/schema.rb \
  core_matrix/app/models/agent_control_mailbox_item.rb \
  core_matrix/app/services/agent_control/create_execution_assignment.rb \
  core_matrix/app/services/agent_control/create_resource_close_request.rb \
  core_matrix/app/services/agent_control/serialize_mailbox_item.rb \
  core_matrix/test/models/agent_control_mailbox_item_test.rb \
  core_matrix/test/requests/agent_api/control_poll_test.rb \
  core_matrix/test/test_helper.rb
git commit -m "refactor: persist mailbox routing semantics explicitly"
```

## Task 2: Make Poll And Publish Use One Explicit Routing Contract

**Files:**

- Modify: `core_matrix/app/services/agent_control/resolve_target_runtime.rb`
- Modify: `core_matrix/app/services/agent_control/poll.rb`
- Modify: `core_matrix/app/services/agent_control/publish_pending.rb`
- Modify: `core_matrix/test/services/agent_control/poll_test.rb`
- Create: `core_matrix/test/services/agent_control/publish_pending_test.rb`
- Modify: `core_matrix/test/requests/agent_api/control_poll_test.rb`

**Step 1: Write the failing tests**

Add tests proving:

- `Poll` selects environment-plane rows by durable columns, not JSON payload
- `ResolveTargetRuntime` owns delivery-endpoint resolution for both planes
- `PublishPending` routes through the same resolver and does not re-open routing
  rules independently
- a deployment attached to the wrong execution environment cannot receive
  environment-plane work even if payload content would otherwise match

Example expectation:

```ruby
delivered_item = AgentControl::PublishPending.call(mailbox_item: environment_plane_item)

assert_equal expected_environment_deployment, delivered_item.leased_to_agent_deployment
assert_equal "leased", delivered_item.status
```

Prefer behavior tests that prove routing semantics directly; do not rely on
source introspection.

**Step 2: Run tests to verify they fail**

Run:

```bash
cd core_matrix
bin/rails test \
  test/services/agent_control/poll_test.rb \
  test/services/agent_control/publish_pending_test.rb \
  test/requests/agent_api/control_poll_test.rb
```

Expected: FAIL because poll still routes through payload JSON logic.

**Step 3: Write the minimal implementation**

Implement:

- `ResolveTargetRuntime` as the shared routing contract owner
- `Poll` candidate selection against durable mailbox columns and indexes
- `PublishPending` through the same shared resolver
- no duplicated agent-plane versus environment-plane routing logic outside the
  resolver family

**Step 4: Run tests to verify they pass**

Run the same command and confirm PASS.

**Step 5: Grep audit**

Run:

```bash
cd core_matrix
rg -n "payload ->> 'runtime_plane'|payload ->> \"runtime_plane\"|execution_environment_id' =" app test
rg -n "inferred_runtime_plane" app test
```

Expected: no remaining runtime routing by JSON payload and no runtime-plane
inference helper.

**Step 6: Commit**

```bash
git add core_matrix/app/services/agent_control/resolve_target_runtime.rb \
  core_matrix/app/services/agent_control/poll.rb \
  core_matrix/app/services/agent_control/publish_pending.rb \
  core_matrix/test/services/agent_control/poll_test.rb \
  core_matrix/test/services/agent_control/publish_pending_test.rb \
  core_matrix/test/requests/agent_api/control_poll_test.rb
git commit -m "refactor: unify mailbox routing for poll and publish"
```

## Task 3: Split Control Report Handling By Family Behind One Thin Ingress Shell

**Files:**

- Create: `core_matrix/app/services/agent_control/report_dispatch.rb`
- Create: `core_matrix/app/services/agent_control/handle_execution_report.rb`
- Create: `core_matrix/app/services/agent_control/handle_close_report.rb`
- Create: `core_matrix/app/services/agent_control/handle_health_report.rb`
- Create: `core_matrix/app/services/agent_control/validate_execution_report_freshness.rb`
- Create: `core_matrix/app/services/agent_control/validate_close_report_freshness.rb`
- Modify: `core_matrix/app/services/agent_control/report.rb`
- Modify: `core_matrix/test/services/agent_control/report_test.rb`
- Modify: `core_matrix/test/requests/agent_api/resource_close_test.rb`
- Modify: `core_matrix/test/requests/agent_api/execution_delivery_test.rb`

**Step 1: Write the failing tests**

Add tests proving:

- `AgentControl::Report` still performs idempotent receipt creation and stale
  translation
- execution reports route through an execution handler family
- close reports route through a close handler family
- health reports route through a health handler family
- execution and close freshness checks live outside the ingress shell

Example expectation:

```ruby
result = AgentControl::Report.call(...)

assert_equal "accepted", result.code
assert_equal "completed", mailbox_item.reload.status
assert_kind_of AgentControl::HandleCloseReport, dispatched_handler
```

Use behavior-level assertions or test doubles as appropriate; do not rely on
fragile constant-name inspection alone.

**Step 2: Run tests to verify they fail**

Run:

```bash
cd core_matrix
bin/rails test \
  test/services/agent_control/report_test.rb \
  test/requests/agent_api/resource_close_test.rb \
  test/requests/agent_api/execution_delivery_test.rb
```

Expected: FAIL because the handler split does not exist yet.

**Step 3: Write the minimal implementation**

Implement:

- `Report` as a thin shell for:
  - touch activity
  - duplicate detection
  - receipt creation
  - stale error translation
  - polling response assembly
- `ReportDispatch` mapping `method_id` to the correct handler family
- execution handler for:
  - assignment acceptance
  - progress
  - terminal execution
- close handler for:
  - close acknowledgment
  - close terminalization
  - resource-specific terminal side effects
- health handler for deployment health updates
- family-specific freshness validators so staleness rules stop growing inside
  the ingress shell

**Step 4: Run tests to verify they pass**

Run the same command and confirm PASS.

**Step 5: Commit**

```bash
git add core_matrix/app/services/agent_control/report_dispatch.rb \
  core_matrix/app/services/agent_control/handle_execution_report.rb \
  core_matrix/app/services/agent_control/handle_close_report.rb \
  core_matrix/app/services/agent_control/handle_health_report.rb \
  core_matrix/app/services/agent_control/validate_execution_report_freshness.rb \
  core_matrix/app/services/agent_control/validate_close_report_freshness.rb \
  core_matrix/app/services/agent_control/report.rb \
  core_matrix/test/services/agent_control/report_test.rb \
  core_matrix/test/requests/agent_api/resource_close_test.rb \
  core_matrix/test/requests/agent_api/execution_delivery_test.rb
git commit -m "refactor: split control report handling by family"
```

## Task 4: Prove Lifecycle Ownership Across Execution And Close Protocols

**Files:**

- Modify: `core_matrix/test/e2e/protocol/turn_interrupt_e2e_test.rb`
- Modify: `core_matrix/test/e2e/protocol/conversation_close_e2e_test.rb`
- Modify: `core_matrix/test/e2e/protocol/process_close_escalation_e2e_test.rb`
- Modify: `core_matrix/test/services/agent_control/report_test.rb`

**Step 1: Write the failing tests**

Add or strengthen end-to-end coverage so it proves:

- execution reports only mutate the accepted holder deployment's lifecycle path
- environment-plane close reports are only accepted from the owning execution
  environment
- close terminalization still re-enters close reconciliation exactly once
- duplicate and stale reports keep the same external HTTP/result semantics
  after the handler split

**Step 2: Run tests to verify they fail**

Run:

```bash
cd core_matrix
bin/rails test \
  test/e2e/protocol/turn_interrupt_e2e_test.rb \
  test/e2e/protocol/conversation_close_e2e_test.rb \
  test/e2e/protocol/process_close_escalation_e2e_test.rb \
  test/services/agent_control/report_test.rb
```

Expected: FAIL until routing and handler ownership are fully aligned.

**Step 3: Write the minimal implementation**

Tighten any remaining drift so:

- execution lifecycle writes only happen through the execution handler family
- close lifecycle writes only happen through the close handler family
- shared freshness validators gate stale delivery consistently
- no sibling code path bypasses the routing contract or handler family

**Step 4: Run tests to verify they pass**

Run the same command and confirm PASS.

**Step 5: Commit**

```bash
git add core_matrix/test/e2e/protocol/turn_interrupt_e2e_test.rb \
  core_matrix/test/e2e/protocol/conversation_close_e2e_test.rb \
  core_matrix/test/e2e/protocol/process_close_escalation_e2e_test.rb \
  core_matrix/test/services/agent_control/report_test.rb
git commit -m "test: lock control-plane lifecycle ownership coverage"
```

## Task 5: Update Behavior Docs, Audit Artifacts, And Final Verification

**Files:**

- Modify: `core_matrix/docs/behavior/agent-runtime-resource-apis.md`
- Modify: `core_matrix/docs/behavior/workflow-scheduler-and-wait-states.md`
- Modify: `docs/reports/core-matrix-architecture-health-audit-register.md`
- Modify: `docs/reports/2026-03-27-core-matrix-architecture-health-audit-round-1.md`

**Step 1: Update docs**

Document explicitly:

- mailbox routing semantics are durable mailbox-row fields
- environment-plane targeting is explicit and installation-scoped
- `AgentControl::Report` is now a thin ingress shell
- execution and close lifecycle handling are delegated to family-specific
  handlers

**Step 2: Run focused verification**

Run:

```bash
cd core_matrix
bin/rails test \
  test/models/agent_control_mailbox_item_test.rb \
  test/services/agent_control/poll_test.rb \
  test/services/agent_control/publish_pending_test.rb \
  test/services/agent_control/report_test.rb \
  test/requests/agent_api/control_poll_test.rb \
  test/requests/agent_api/resource_close_test.rb \
  test/requests/agent_api/execution_delivery_test.rb \
  test/e2e/protocol/turn_interrupt_e2e_test.rb \
  test/e2e/protocol/conversation_close_e2e_test.rb \
  test/e2e/protocol/process_close_escalation_e2e_test.rb
```

Then run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
git diff --check
```

**Step 3: Commit**

```bash
git add core_matrix/docs/behavior/agent-runtime-resource-apis.md \
  core_matrix/docs/behavior/workflow-scheduler-and-wait-states.md \
  docs/reports/core-matrix-architecture-health-audit-register.md \
  docs/reports/2026-03-27-core-matrix-architecture-health-audit-round-1.md
git commit -m "docs: record control-plane routing unification"
```

## Task 6: Mandatory Three-Pass Completeness Review Before Declaring The Batch Ready

This task is required both while implementing and again before claiming the
batch is complete. Do not skip it.

### Pass 1: Scope And Files Review

Re-read this plan and the touched diff. Confirm:

- every file listed in `Anticipated File Set` was either changed or explicitly
  ruled out with a written reason in the implementation notes
- the migration edit, `db/schema.rb`, and database reset were actually done
- no compatibility fallback kept payload-based routing alive

### Pass 2: Contract And Behavior Review

Confirm:

- mailbox rows own routing semantics directly
- `ResolveTargetRuntime`, `Poll`, and `PublishPending` all use one routing
  contract
- `AgentControl::Report` is only the ingress shell
- execution and close lifecycle behavior are split into the intended handler
  families
- docs reflect the new routing and lifecycle owners accurately

### Pass 3: Tests And Audit Review

Confirm:

- every test command in this plan was run
- failures were resolved without weakening the target shape
- grep audits came back clean
- the audit register and Round 1 report were updated consistently
- there is no missing use case, missing task, missing doc update, missing file,
  or missing verification command that was implied by this conversation

If any pass finds a gap, update code, docs, or this plan's execution notes and
repeat the affected pass until no issue remains. The batch is not ready until
all three passes are clean.

## Acceptance Criteria

- mailbox routing semantics are stored as durable mailbox columns, not inferred
  from payload.
- environment-plane delivery no longer depends on JSON payload routing.
- `AgentControl::Report` is a thin ingress shell with family-specific handlers.
- stale validation is explicit and family-specific.
- targeted tests, neighboring tests, schema reset, grep audits, and doc updates
  all pass.
