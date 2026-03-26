# Core Matrix Review Audit Findings

## Scope

- Refresh date: `2026-03-27`
- Refresh baseline: post-fix state after `fix: harden turn interrupt fences`
  (`7b3f7b6`)
- In scope: Ruby code under `app/`, `lib/`, `config/`, `db/`, and `test/`
- Out of scope: frontend work, compiled assets, and non-Ruby code
- Review goals:
  - identify leftover or transitional development code
  - identify Ruby and Rails philosophy drift
  - identify potential risks in boundaries, lifecycle, callbacks, transactions,
    exception handling, and tests
- Review method:
  - primary pass: runtime and layering review
  - reverse pass: cross-cutting rules and tests
  - no category is considered complete until it has been checked from both
    directions
- Pre-screen targets from the refreshed global scan:
  - large production files:
    - `app/services/agent_control/report.rb`
    - `app/models/conversation.rb`
    - `app/services/provider_execution/execute_turn_step.rb`
    - `app/services/workflows/context_assembler.rb`
    - `app/services/installations/register_bundled_agent_runtime.rb`
  - high-yield namespaces by volume or signal density:
    - `app/services/conversations`
    - `app/services/workflows`
    - `app/services/turns`
    - `app/services/agent_deployments`
    - `app/services/agent_control`
  - targeted follow-up areas:
    - recovery paths that rebind or restart workflow execution
    - turn-entry services that accept `agent_deployment`
    - wait-state blocker identifier semantics
    - turn-history rewrite helpers that can mutate terminal turns

## Findings

Execution follow-up note:

- later implementation work on this refresh also surfaced two sibling paths
  that fit the same runtime-binding defect family:
  - `AgentDeployments::AutoResumeWorkflows`
  - `Turns::StartAutomationTurn`
- they were folded into the same hardening batch rather than treated as
  separate later cleanup
### Must Fix

1. `Workflows::ManualRetry` can rebind a paused workflow to a deployment
   outside the conversation's bound execution environment, and the current test
   suite codifies that drift as valid.
   - Why it matters: the retry path can create a new turn and workflow whose
     execution identity pairs
     `conversation.execution_environment.public_id` with an unrelated
     `turn.agent_deployment.public_id`, while the conversation-level runtime
     contract still remains bound to the original deployment. That breaks the
     runtime-binding contract and can route recovered work through the wrong
     environment boundary.
   - Evidence:
     - `app/services/workflows/manual_retry.rb:16-43`
     - `app/services/workflows/manual_retry.rb:70-73`
     - `app/services/turns/start_user_turn.rb:17-50`
     - `app/services/turns/queue_follow_up.rb:17-54`
     - `app/models/turn.rb:29-49`
     - `app/services/workflows/context_assembler.rb:37-45`
     - `app/services/conversations/switch_agent_deployment.rb:14-38`
     - `test/services/conversations/switch_agent_deployment_test.rb:28-52`
     - `test/integration/agent_recovery_flow_test.rb:51-60`
     - `test/integration/agent_recovery_flow_test.rb:76-99`
   - Reasoning basis: `ManualRetry` validates only installation membership,
     scheduling eligibility, and input presence, then passes the replacement
     deployment straight into `Turns::StartUserTurn`. `Turn` only validates
     installation matching, not execution-environment binding. `ContextAssembler`
     then serializes the conversation's environment and the turn's deployment
     side by side. The current integration recovery test explicitly builds the
     replacement deployment in a fresh execution environment and expects the
     retry to succeed, while `SwitchAgentDeployment` rejects the same
     cross-environment move.
   - Recommended action: make manual retry enforce the same environment guard as
     `Conversations::SwitchAgentDeployment`, decide whether retry must also move
     the conversation's active deployment to the replacement target, and add
     negative tests for cross-environment retry targets in
     `manual_retry_test.rb` and `agent_recovery_flow_test.rb`.

## Suggestions

1. `WorkflowRun#blocking_resource_id` is still semantically inconsistent across
   wait-state producers.
   - Evidence:
     - `app/services/agent_deployments/unavailable_pause_state.rb:5-17`
     - `test/services/agent_deployments/mark_unavailable_test.rb:14-21`
     - `app/services/human_interactions/request.rb:67-74`
     - `app/services/agent_control/report.rb:279-290`
     - `app/services/workflows/scheduler.rb:97-104`
   - Why it matters: agent-unavailable pauses still write an internal
     `AgentDeployment.id`, while human-interaction, retryable-failure, and
     policy-gate waits use `public_id`. That inconsistency makes generic
     wait-state handling harder and risks future identifier leaks if any
     external or agent-facing read path serializes this field without special
     cases.
   - Suggested action: normalize the agent-unavailable path to
     `AgentDeployment.public_id`, or explicitly split the field contract so raw
     internal ids are never mixed with externally shaped blocker references.

2. Turn-history rewrite helpers can reactivate turns without checking retention,
   archive/delete state, or close fences.
   - Evidence:
     - `app/services/turns/retry_output.rb:12-35`
     - `app/services/turns/rerun_output.rb:12-78`
     - `test/services/turns/retry_output_test.rb:4-29`
     - `test/services/turns/rerun_output_test.rb:4-64`
   - Why it matters: `RetryOutput` and in-place `RerunOutput` both create new
     transcript messages and move a turn back to `active`, but they do not
     re-check conversation retention, archive/delete lifecycle, or
     `turn_interrupted` fences. They are only covered by happy-path tests today,
     so the services could resurrect superseded turns if they are wired into a
     product surface later.
   - Suggested action: add the same retained/active/closing guards used by
     turn-entry services, and add negative tests for archived, pending-delete,
     and interrupted turns before these helpers are exposed more broadly.

## Watch List

1. `AgentControl::Report` remains a large multi-role orchestrator.
   - `app/services/agent_control/report.rb` still owns mailbox validation,
     receipt idempotency, execution state transitions, retry-gate updates,
     resource-close transitions, lease handling, and close-operation
     reconciliation.

2. `Conversation` is still carrying multiple abstractions in one Active Record
   model.
   - `app/models/conversation.rb` still mixes projection assembly, lineage
     traversal, runtime-contract access, deletion-state validation, and
     interactive selector rules.

## Cross-check Summary

- Global signal scan notes:
  - the previous purge-chain omission now appears fixed in
    `Conversations::PurgePlan`, and `purge_deleted_test.rb` now exercises
    phase-two agent-control residue explicitly
  - the recent interrupt/provider fence fixes are present in code and no longer
    stand out as unresolved scan targets
  - the strongest new signal comes from recovery and turn-entry paths because
    `ManualRetry` validates materially less than `ManualResume`, and the
    integration recovery test currently accepts a replacement deployment from a
    fresh execution environment
  - wait-state blocker identifiers still diverge between agent-unavailable and
    the other blocker families
- Reverse-pass confirmations:
  - `bin/rails test test/services/workflows/manual_retry_test.rb test/integration/agent_recovery_flow_test.rb test/services/turns/start_user_turn_test.rb test/services/turns/queue_follow_up_test.rb`
    currently passes as
    `11 runs, 61 assertions, 0 failures, 0 errors, 0 skips`, confirming that no
    cross-environment rejection exists today
  - `SwitchAgentDeployment` explicitly rejects cross-environment deployment
    moves, which makes `ManualRetry` accepting them a contract inconsistency,
    not a shared product rule
  - the turn-history rewrite tests cover only happy paths and do not challenge
    retained/archived/deleted/interrupted state

## Completeness Check

- Goal coverage:
  - leftover-code review refreshed
  - Ruby and Rails philosophy review refreshed
  - potential-risk review refreshed
- Scope coverage:
  - re-reviewed the highest-yield service areas under `app/services/turns`,
    `app/services/workflows`, `app/services/agent_deployments`,
    `app/services/conversations`, and `app/services/agent_control`
  - spot-checked the current larger model target in `app/models/conversation.rb`
- Double-check coverage:
  - findings were identified from code and contract drift first
  - findings were then checked against existing tests, sibling services, and
    contrasting guard paths
- Artifact completeness:
  - the current evidence-backed conclusions are written in this document
  - blocking defects are separated from suggestions and watch-list items
- Residual limitations:
  - this refresh used targeted Rails test suites, not the full project test
    suite
  - no `bin/dev` or live-runtime manual validation was performed in this round
