# Core Matrix Phase 2 Test Strategy Design

## Status

Focused design note for Phase 2 verification strategy.

## Purpose

Phase 2 introduces a mailbox-driven control protocol, turn interruption,
conversation close orchestration, step retry, and transport fallback behavior.
Those risks live primarily in protocol and state-machine boundaries, not in a
browser UI.

This design freezes the verification split:

- Phase 2 proves backend protocol and state-machine correctness through
  protocol-oriented tests plus real-environment manual validation
- Phase 3 introduces browser-facing UI end-to-end tests for Web product
  surfaces

The goal is to keep Phase 2 test investment aligned with kernel risk and avoid
mixing protocol confidence with future UI productization work.

## Testing Split

### Phase 2: Protocol E2E

Phase 2 must treat `Core Matrix <-> agent program` communication as its primary
end-to-end test surface.

`Protocol E2E` means:

- no browser UI
- no DOM assertions
- no dependency on future Web product routes or controls
- one real Rails app instance
- one headless runtime harness that behaves like an agent program
- the same mailbox semantics exercised through:
  - `poll`
  - `WebSocket`
  - response piggyback

The purpose of Protocol E2E is to prove:

- mailbox delivery correctness
- durable lease and retry semantics
- interrupt and close fences
- archive and delete close orchestration
- process and MCP close behavior
- presence versus control-activity distinctions

### Phase 3: UI E2E

Browser-facing `UI E2E` belongs to Web UI productization, not to Phase 2.

`UI E2E` should validate:

- conversation list and detail screens
- stop, archive, and delete user flows
- warning and degraded-state presentation
- human-interaction product surfaces
- retry and operator prompts exposed through the Web UI

Phase 2 must not depend on these tests for completion.

## Required Phase 2 Test Layers

Phase 2 should use four explicit verification layers.

### L0: State-Machine Unit Tests

Purpose:

- verify durable model and service transitions without transport concerns

Examples:

- mailbox item lifecycle
- lease expiry and redelivery bookkeeping
- `ConversationCloseOperation` transitions
- closable resource `close_*` field updates
- close fence behavior

### L1: Protocol Contract Tests

Purpose:

- verify one logical mailbox envelope behaves consistently across transports

Examples:

- the same `execution_assignment` envelope delivered via `poll` and
  `WebSocket`
- duplicate message handling by `message_id`
- `delivery_no` versus `attempt_no`
- response piggyback semantics

### L2: Protocol E2E

Purpose:

- prove realistic protocol and state-machine behavior across multiple
  round-trips and failure modes

This layer should start a real `Core Matrix` app process and use a headless
runtime harness instead of a browser.

Milestone ownership:

- Milestone C must establish the protocol-E2E harness, transport test paths,
  and the first mailbox or close golden scenarios
- later Phase 2 milestones should extend the same protocol-E2E suite rather
  than creating parallel end-to-end infrastructure

### L3: Manual Real-Environment Validation

Purpose:

- verify the milestone under `bin/dev`, with real credentials and operator
  procedures

This layer continues to use:

- `docs/checklists/2026-03-24-core-matrix-kernel-manual-validation.md`
- committed proof artifacts under `docs/reports/phase-2/`

## Protocol E2E Infrastructure

Phase 2 should add dedicated protocol-E2E support rather than reusing browser
or future UI harnesses.

Recommended locations:

- `core_matrix/test/e2e/protocol/*`
- `core_matrix/test/support/fake_agent_runtime_harness.rb`
- `core_matrix/test/support/mailbox_scenario_builder.rb`
- `core_matrix/test/support/controllable_clock.rb`
- `core_matrix/test/support/fake_external_process_runner.rb`
- `core_matrix/test/support/fake_mcp_runtime.rb`

### Fake Agent Runtime Harness

The harness should support:

- `WebSocket` session open and disconnect
- `agent_poll`
- response piggyback processing
- duplicate report emission
- late report emission
- explicit close acknowledgement
- explicit close failure
- long-running execution simulation
- expected-duration and timeout scenarios

### Controllable Clock

Mailbox deadlines are first-class Phase 2 behavior.

Tests must be able to deterministically advance:

- dispatch deadlines
- lease timeouts
- execution hard deadlines
- close grace deadlines
- close force deadlines

Do not rely on long sleeps in protocol E2E.

## Required Phase 2 Protocol E2E Scenarios

At minimum, the protocol E2E suite should cover the following golden paths.

### Delivery And Presence

1. `poll`-only execution assignment, progress, and completion
2. `WebSocket` delivery with identical mailbox envelope shape
3. `WebSocket` disconnect followed by successful `poll` fallback
4. `WebSocket` disconnect while control activity remains `active` through poll
   or progress

### Idempotency And Late Reports

5. duplicate `execution_complete` handled idempotently
6. duplicate `resource_closed` handled idempotently
7. late `execution_progress` after close fence rejected as stale or
   superseded
8. late terminal report after `turn_interrupt` not allowed to mutate turn
   outcome

### Retry Semantics

9. retryable step failure moves workflow into `retryable_failure`
10. `step_retry` creates a new attempt inside the same turn and workflow
11. `turn_interrupt` fences pending `step_retry`
12. close requests outrank queued retry work

### Close And Disposal

13. `turn_interrupt` clears the mainline stop barrier only
14. `archive(force: true)` reaches `archived` once mainline work stops
15. `archive(force: true)` may finish with degraded disposal residue
16. `delete` enters `pending_delete` immediately and later finalizes
17. parent delete does not cascade to retained child
18. ancestor purge remains blocked by descendant lineage

### Process And Connection Closure

19. `ProcessRun(kind = turn_command)` graceful interrupt success
20. graceful interrupt timeout followed by forced termination success
21. forced termination failure recorded as `residual_abandoned`
22. detached background process not affected by plain `turn_interrupt`
23. in-flight MCP or long-lived network call closed by cancel or connection
    abort with durable terminal outcome

## Phase 2 Verification Rules

The Phase 2 task set should obey these rules:

- Protocol E2E is a Milestone C responsibility, not a final-acceptance-only
  concern
- mailbox and close work must add L0, L1, and L2 coverage together
- provider-backed execution is not complete without protocol-E2E coverage for
  delivery and late-report behavior added onto the Milestone C harness
- archive and delete work is not complete without protocol-E2E coverage for
  stop, disposal, and residual cases added onto the same harness
- manual validation is milestone acceptance evidence, not a substitute for
  protocol E2E
- browser UI assertions are out of scope for Phase 2

## Directory And Naming Rules

Recommended naming:

- `Protocol E2E` for Phase 2 protocol end-to-end coverage
- `UI E2E` for future browser-facing coverage

Avoid using `system test` or `integration test` alone as the only label when a
test is specifically validating mailbox protocol behavior. The directory and
test name should make that purpose explicit.

## Relationship To Existing Manual Validation

The existing manual validation baseline remains authoritative for operator
reproducibility, but it should not absorb protocol-E2E responsibilities.

Phase 2 should keep both:

- deterministic protocol-E2E coverage in the automated suite
- committed manual proof artifacts and `bin/dev` validation for milestone
  acceptance

## Non-Goals

- building Playwright or browser automation infrastructure in Phase 2
- proving Web UI interactions before Phase 3 Web productization
- replacing manual acceptance artifacts with automated screenshots
- turning protocol E2E into a generic distributed-systems framework

## Related Documents

- [2026-03-26-core-matrix-conversation-close-and-mailbox-control-protocol-design.md](/Users/jasl/Workspaces/Ruby/cybros/docs/design/2026-03-26-core-matrix-conversation-close-and-mailbox-control-protocol-design.md)
- [2026-03-26-core-matrix-phase-2-plan-agent-loop-execution.md](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-26-core-matrix-phase-2-plan-agent-loop-execution.md)
- [2026-03-26-core-matrix-phase-2-task-mailbox-control-and-resource-close-contract.md](/Users/jasl/Workspaces/Ruby/cybros/docs/finished-plans/2026-03-26-core-matrix-phase-2-task-mailbox-control-and-resource-close-contract.md)
- [2026-03-26-core-matrix-phase-2-task-turn-interrupt-and-conversation-close-semantics.md](/Users/jasl/Workspaces/Ruby/cybros/docs/finished-plans/2026-03-26-core-matrix-phase-2-task-turn-interrupt-and-conversation-close-semantics.md)
- [2026-03-25-core-matrix-phase-2-task-run-verification-and-manual-acceptance.md](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-25-core-matrix-phase-2-task-run-verification-and-manual-acceptance.md)
