# Core Matrix Phase 2 Control-Plane Routing And Lifecycle Ownership Closeout Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Finish the post-landing hardening for the control-plane routing and lifecycle ownership batch, prove the remaining request-boundary regressions end-to-end, and retire this track from active implementation planning.

**Architecture:** The main control-plane unification is already landed. Durable mailbox routing now lives on the mailbox row, `ResolveTargetRuntime` is shared by poll and publish, and `AgentControl::Report` already delegates execution, close, and health report handling to dedicated families. The remaining work is a closeout pass: add the last request-boundary regression coverage, re-scan active docs and audit artifacts for drift, and mark the track ready for retirement from active plans.

**Tech Stack:** Ruby on Rails (`core_matrix`), Active Record, Minitest service/request/e2e coverage, behavior docs, audit artifacts, grep-based verification

---

## Current Baseline

This plan is intentionally re-baselined to the current workspace state as of
`2026-03-28`. The following work is already landed and must not be planned
again as if it were missing:

- mailbox rows already persist:
  - `runtime_plane`
  - `target_kind`
  - `target_ref`
  - optional `target_execution_environment_id`
- mailbox routing no longer depends on payload inference or JSON SQL routing
- `ResolveTargetRuntime.candidate_scope_for` is already shared by `Poll`
- `PublishPending` already routes through `ResolveTargetRuntime`
- `AgentControl::Report` is already a thin ingress shell
- `ReportDispatch`, `HandleExecutionReport`, `HandleCloseReport`,
  `HandleHealthReport`, `ValidateExecutionReportFreshness`, and
  `ValidateCloseReportFreshness` already exist
- active behavior docs already describe the durable routing contract at a high
  level

## Remaining Problems To Close

The architecture shift is complete, but a small closeout batch still makes
sense:

- the active plan should no longer pretend the main implementation is still
  missing
- the strongest remaining risk is regression at the request boundary:
  environment-plane close reports must still fail safe when a deployment from
  the wrong execution environment tries to report while spoofing payload data
- active docs and audit artifacts should be re-scanned and only updated if they
  still describe payload inference or a monolithic `AgentControl::Report` as
  current behavior

## Execution Rules

- Treat this as a regression-hardening and retirement batch, not as a second
  implementation of the control-plane unification.
- Do not recreate durable routing columns or the handler split that already
  landed.
- Keep the routing contract centered on durable mailbox fields, not on payload
  conventions.
- Prefer request-boundary regressions over more unit-level source inspection;
  the remaining value is proving the end-to-end shell still respects the landed
  contract.
- Active docs and active audit artifacts must describe the current owners.
  Historical finished plans may retain older names when they are explicitly
  describing the past.
- Final verification is not complete until:
  - app code has no payload-based runtime-plane routing
  - the request boundary proves wrong-environment close reports are rejected
    even when payload content is spoofed
  - active docs and audit artifacts do not describe payload inference or the
    old monolithic report sink as current behavior

## Anticipated File Set

### Modify

- `core_matrix/test/requests/agent_api/resource_close_test.rb`
- `core_matrix/test/services/agent_control/report_test.rb`
  only if the request-level hardening needs matching service-level assertions
- `core_matrix/docs/behavior/agent-runtime-resource-apis.md`
  only if the grep sweep finds stale wording
- `core_matrix/docs/behavior/workflow-scheduler-and-wait-states.md`
  only if the grep sweep finds stale wording
- `docs/reports/core-matrix-architecture-health-audit-register.md`
  only if the grep sweep finds stale wording
- `docs/reports/2026-03-27-core-matrix-architecture-health-audit-round-1.md`
  only if the grep sweep finds stale wording

## Task 1: Add The Final Request-Boundary Regression For Environment-Plane Close Reports

**Files:**

- Modify: `core_matrix/test/requests/agent_api/resource_close_test.rb`
- Modify: `core_matrix/test/services/agent_control/report_test.rb`
  only if the request test exposes a matching service-level gap

**Step 1: Write the regression test first**

Add a request-level regression that proves:

- a deployment attached to the wrong execution environment cannot submit an
  accepted environment-plane close report
- spoofed payload content does not override the mailbox row's durable routing
  fields
- the target resource and mailbox item remain unchanged after the rejected
  report

Example expectation:

```ruby
post "/agent_api/control/report", params: spoofed_params, ...

assert_response :conflict
assert_equal "stale", JSON.parse(response.body).fetch("result")
assert_equal "requested", process_run.reload.close_state
assert_equal "leased", mailbox_item.reload.status
```

**Step 2: Run the regression and verify the current boundary**

Run:

```bash
cd core_matrix
bin/rails test \
  test/requests/agent_api/resource_close_test.rb
```

Expected: FAIL if the request boundary is still missing this regression.
If the new test passes immediately, treat that as confirmation that the
request boundary already enforces the landed contract and skip directly to the
doc sweep plus final verification.

**Step 3: Write the minimal implementation**

If the new request test exposes a gap, fix it at the narrowest current owner:

- prefer `ValidateCloseReportFreshness` if the stale check is incomplete
- prefer request or test fixture cleanup if the implementation is already
  correct and only the test setup was missing
- do not widen `AgentControl::Report` again

**Step 4: Run tests to verify they pass**

Run the same command and confirm PASS.

**Step 5: Commit**

```bash
git add core_matrix/test/requests/agent_api/resource_close_test.rb \
  core_matrix/test/services/agent_control/report_test.rb
git commit -m "test: harden control report environment-plane regressions"
```

If `report_test.rb` did not need changes, omit it from the commit.

## Task 2: Re-Scan Active Docs And Audit Artifacts For Drift

**Files:**

- Modify: `core_matrix/docs/behavior/agent-runtime-resource-apis.md`
  only if stale wording remains
- Modify: `core_matrix/docs/behavior/workflow-scheduler-and-wait-states.md`
  only if stale wording remains
- Modify: `docs/reports/core-matrix-architecture-health-audit-register.md`
  only if stale wording remains
- Modify: `docs/reports/2026-03-27-core-matrix-architecture-health-audit-round-1.md`
  only if stale wording remains

**Step 1: Run the doc and code sweep**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
rg -n "inferred_runtime_plane|payload ->> 'runtime_plane'|payload ->> \"runtime_plane\"|AgentControl::Report is acting as a large ingress shell|payload inference" \
  core_matrix/app \
  core_matrix/docs/behavior \
  docs/reports
```

Interpretation:

- app-code hits should be treated as real drift
- active behavior docs and active audit artifacts should describe the current
  owners, not the pre-unification shape
- historical finished plans are out of scope

**Step 2: Update docs only where needed**

If the sweep finds stale wording, update the active docs so they describe:

- durable mailbox-row routing fields
- `ResolveTargetRuntime` as the shared routing contract
- `AgentControl::Report` as the ingress shell
- dedicated execution / close / health handler families as the lifecycle
  owners

**Step 3: Re-run the sweep**

Run the same grep command again and confirm any remaining hits are either
current implementation references or explicitly historical context.

**Step 4: Commit**

```bash
git add core_matrix/docs/behavior/agent-runtime-resource-apis.md \
  core_matrix/docs/behavior/workflow-scheduler-and-wait-states.md \
  docs/reports/core-matrix-architecture-health-audit-register.md \
  docs/reports/2026-03-27-core-matrix-architecture-health-audit-round-1.md
git commit -m "docs: close out control-plane ownership references"
```

Only include files that actually changed.

## Task 3: Final Verification And Retirement Readiness

**Step 1: Run focused verification**

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
  test/requests/agent_api/execution_delivery_test.rb
```

Then run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
rg -n "inferred_runtime_plane|payload ->> 'runtime_plane'|payload ->> \"runtime_plane\"" core_matrix/app core_matrix/docs/behavior docs/reports
git diff --check
```

**Step 2: Retirement review**

Confirm:

- the control-plane routing / lifecycle ownership track no longer needs an
  active implementation plan in `docs/plans`
- any remaining references in audit artifacts are historical diagnosis, not
  current-state description
- the only surviving payload `runtime_plane` references in tests are
  intentional spoof regressions or envelope assertions, not production routing

When this closeout plan is fully executed, move it out of active planning
alongside the other finished implementation artifacts.

## Acceptance Criteria

- the request boundary rejects wrong-environment environment-plane close
  reports even when payload content is spoofed.
- app code has no payload-based runtime-plane routing left.
- active docs and active audit artifacts describe the current routing and
  lifecycle owners correctly.
- focused service and request tests pass.
- `git diff --check` passes.

## Completion Record

- Status: completed
- Completion date: 2026-03-28
- Retirement note: moved out of `docs/plans` after the third-round
  completeness review confirmed the remaining request-boundary hardening had
  already landed and the active plan was stale.
- Landing commits:
  - `ab6131f` `refactor: unify mailbox routing for poll and publish`
  - `3a00781` `refactor: split control report handling by family`
  - `687ddf1` `docs: record control-plane routing unification`
  - `cc07a5d` `test: harden control-plane ingress coverage`
  - `b033b4e` `test: cover wrong-environment close report rejection`
- Landed scope:
  - durable mailbox routing lives on mailbox-row fields, with
    `ResolveTargetRuntime` shared by poll and publish.
  - `AgentControl::Report` remains a thin ingress shell while execution, close,
    and health lifecycle handling is split across dedicated handler families and
    freshness validators.
  - the wrong-environment environment-plane close-report regression is covered
    at the request boundary and rejects spoofed payload routing data.
- Review corrections on 2026-03-28:
  - the active plan was retired because the purported final missing regression
    already existed in `core_matrix/test/requests/agent_api/resource_close_test.rb`.
  - the focused control-plane verification suite was rerun during the review to
    confirm the retirement decision against current `HEAD`.
- Verification evidence:
  - `cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && bin/rails test test/models/agent_control_mailbox_item_test.rb test/services/agent_control/poll_test.rb test/services/agent_control/publish_pending_test.rb test/services/agent_control/report_test.rb test/requests/agent_api/control_poll_test.rb test/requests/agent_api/resource_close_test.rb test/requests/agent_api/execution_delivery_test.rb`
  - `cd /Users/jasl/Workspaces/Ruby/cybros && rg -n "inferred_runtime_plane|payload ->> 'runtime_plane'|payload ->> \"runtime_plane\"" core_matrix/app core_matrix/docs/behavior docs/reports`
  - `cd /Users/jasl/Workspaces/Ruby/cybros && git diff --check`
