# Core Matrix Review Audit Findings

## Scope

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
- Pre-screen targets from the global scan:
  - large production files:
    - `app/services/agent_control/report.rb`
    - `app/controllers/mock_llm/v1/chat_completions_controller.rb`
    - `app/models/conversation.rb`
    - `app/services/provider_catalog/validate.rb`
    - `app/services/provider_execution/execute_turn_step.rb`
    - `app/services/workflows/context_assembler.rb`
    - `app/services/installations/register_bundled_agent_runtime.rb`
  - high-yield namespaces by volume or signal density:
    - `app/services/conversations`
    - `app/services/workflows`
    - `app/services/agent_control`
    - `app/services/provider_execution`
    - `app/services/provider_catalog`
  - targeted follow-up areas:
    - boundary and identifier handling around agent-facing controllers and
      provider execution
    - workflow lifecycle and manual recovery flows
    - conversation model and related conversation services
    - seed/bootstrap paths that may keep transitional runtime logic alive

## Findings

### Must Fix

1. `Conversations::PurgeDeleted` omits the phase-two agent-control tables from
   its manual delete chain.
   - Why it matters: the purge path deletes `workflow_runs` and `turns`
     manually, but it does not delete `agent_task_runs`,
     `agent_control_mailbox_items`, or `agent_control_report_receipts` first.
     Because those rows have foreign keys back to `workflow_runs` and
     `agent_task_runs`, a deleted conversation that ever used agent-control work
     can become unpurgeable or fail with foreign-key violations.
   - Evidence:
     - `app/services/conversations/purge_deleted.rb:84-123`
     - `app/services/conversations/work_quiescence_guard.rb:5-19`
     - `app/services/conversations/finalize_deletion.rb:26-29`
     - `app/models/agent_task_run.rb:25-31`
     - `app/models/agent_control_mailbox_item.rb:31-37`
     - `db/migrate/20260326113000_add_agent_control_contract_for_phase_two.rb:3-40`
     - `db/migrate/20260326113000_add_agent_control_contract_for_phase_two.rb:72-86`
     - `app/services/conversations/request_turn_interrupt.rb:75-86`
     - `test/services/conversations/purge_deleted_test.rb:198-325`
   - Reasoning basis: queued agent tasks are canceled during interrupt flows but
     retained as rows, and the purge tests do not cover any conversation that
     owns `AgentTaskRun` or related mailbox/receipt rows. The current purge list
     therefore predates the phase-two agent-control schema.
   - Recommended action: extend purge cleanup to delete
     `agent_control_report_receipts`, `agent_control_mailbox_items`, and
     `agent_task_runs` in the correct dependency order, then add a purge test
     that exercises a conversation with agent-control task state.

## Suggestions

1. `AgentControl::Report` has drifted into a large multi-role service.
   - Evidence:
     - `app/services/agent_control/report.rb:26-365`
   - Why it matters: one class now owns idempotency receipts, mailbox
     validation, lease handling, execution status transitions, resource-close
     transitions, retry-gate updates, and close-operation reconciliation. That
     makes local changes hard to reason about and increases the chance of
     cross-path regressions.
   - Suggested action: split report handling by method family or resource type,
     leaving this class as orchestration only.

2. `Conversation` is carrying multiple abstractions that do not sit naturally in
   one Active Record model.
   - Evidence:
     - `app/models/conversation.rb:88-140`
     - `app/models/conversation.rb:144-210`
     - `app/models/conversation.rb:213-306`
   - Why it matters: projection assembly, lineage traversal, runtime-contract
     access, deletion-state validation, and provider-catalog validation all live
     in one model, including a `send` call to recurse into another instance's
     private method. This is valid Ruby, but it is not a clean domain boundary.
   - Suggested action: extract projection/query behavior and selector validation
     into dedicated collaborators, leaving the model to own invariants and
     lightweight domain predicates.

3. `MockLLM::V1::ChatCompletionsController` is controller-heavy even for a mock
   endpoint.
   - Evidence:
     - `app/controllers/mock_llm/v1/chat_completions_controller.rb:8-338`
   - Why it matters: request validation, directive parsing, token estimation,
     streaming protocol formatting, environment clamping, and response-building
     all live in the controller. The namespace is intentionally mock-only, so
     this is not a product-correctness defect, but it is clearly outside normal
     Rails controller responsibilities.
   - Suggested action: extract parser and response-builder objects so the
     controller only coordinates request/response flow.

4. `WorkflowRun#blocking_resource_id` no longer has consistent semantics across
   callers.
   - Evidence:
     - `app/services/agent_deployments/mark_unavailable.rb:52-60`
     - `app/services/workflows/step_retry.rb:76`
     - `app/services/agent_control/report.rb:279-289`
     - `test/services/agent_deployments/mark_unavailable_test.rb:14-21`
   - Why it matters: most flows write a resource `public_id` into
     `blocking_resource_id`, but the agent-unavailable path stores
     `AgentDeployment#id.to_s`. That inconsistency is a trap for future generic
     lookup or serialization code, especially in a codebase with an explicit
     `public_id` boundary policy.
   - Suggested action: normalize `blocking_resource_id` to durable external
     identifiers whenever it references a resource with `public_id`, and adjust
     tests to enforce the stable contract.

## Watch List

1. The manual purge path is maintenance-heavy by design.
   - Even after the current missing tables are fixed, `Conversations::PurgeDeleted`
     will remain fragile because every new dependent table must be added to an
     explicit delete list. This should be monitored whenever schema changes land
     in workflow, agent-control, or conversation-related models.

2. Provider execution is still only indirectly tested.
   - `ProviderExecution::ExecuteTurnStep` currently gets exercised through
     `Workflows::ExecuteRun`, which is enough for happy/failure paths but weak
     for state-machine edge cases and repeat-execution guards.

## Cross-check Summary

- Global signal scan notes:
  - explicit debug leftovers were scarce; the only obvious `puts` calls are in
    `db/seeds.rb`, which may be intentional operational output rather than a
    cleanup defect
  - model callback density is low and mostly `before_validation`, so callback
    overuse does not currently look like the first-order risk
  - rescue-heavy code clusters around provider execution, workflow mutation, and
    mock LLM handling, so those paths need closer inspection for swallowed or
    downgraded failures
  - the largest production files line up with the largest service namespaces,
    which raises the likelihood of mixed responsibilities or incomplete cleanup
- Reverse-pass confirmations:
  - the purge-chain omission is confirmed by cross-reading the phase-two schema,
    the `AgentTaskRun`/mailbox associations, and the purge tests; the tests do
    not currently exercise a deleted conversation that owns agent-control task
    state
  - a candidate `ExecuteTurnStep` terminal-state issue was investigated and
    downgraded because the current workflow-node event writers do not establish
    `interrupted` as a confirmed node-event terminal state
  - the agent-facing HTTP controllers reviewed in `app/controllers/agent_api`
    consistently resolve lookups by `public_id` and serialize durable
    identifiers back out as `public_id`, so no confirmed external boundary leak
    was found in those controllers during this pass
  - the `lib/`, `config/`, and `db/` Ruby sweep did not uncover additional
    leftover development branches beyond intentional seed logging and the
    already-noted phase-two purge omission

## Completeness Check

- Goal coverage:
  - leftover-code review completed
  - Ruby and Rails philosophy review completed
  - potential-risk review completed
- Scope coverage:
  - reviewed `app/`, `config/`, `db/`, and `test/` Ruby code
  - `lib/` contains no review-significant Ruby implementation in the current
    project state
- Double-check coverage:
  - findings were first identified from code and structure
  - findings were then re-checked against schema, tests, or sibling-call-site
    behavior
- Artifact completeness:
  - all current conclusions are written in this document
  - each must-fix finding includes evidence and a recommended action
  - non-blocking issues are separated into `Suggestions` and `Watch List`
- Residual limitations:
  - no full automated test suite was run as part of this review
  - no manual runtime validation was performed in `bin/dev`
