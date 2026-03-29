# Core Matrix Phase 2 Milestone D Sequential Execution Plan

> **For Codex:** REQUIRED SUB-SKILL: Use [$executing-plans](/Users/jasl/.codex/skills/executing-plans/SKILL.md) to implement this plan task-by-task.

**Goal:** Land the remaining Phase 2 Milestone D work so the kernel durably owns conversation feature policy, stale-work safety, wait handoff, human interaction, and subagent resume semantics.

**Architecture:** Reuse the existing `Conversation -> Turn -> WorkflowRun -> WorkflowNode` chain and the current wait-state substrate. Do not invent parallel ledgers for feature flags, pause state, or subagent orchestration. Extend the current scheduler and yield-owned workflow resources until yielded runtime requests become durable, auditable kernel state.

**Tech Stack:** Ruby on Rails, Active Record, Minitest, `bin/dev`, OpenRouter-backed provider runs

---

## Required Inputs

- `AGENTS.md`
- `docs/design/2026-03-30-core-matrix-phase-2-sequential-execution-design.md`
- `docs/plans/2026-03-26-core-matrix-phase-2-plan-agent-loop-execution.md`
- `docs/plans/2026-03-25-core-matrix-phase-2-task-conversation-feature-policy-and-stale-work-safety.md`
- `docs/plans/2026-03-25-core-matrix-phase-2-task-wait-state-human-interaction-and-subagents.md`
- `docs/checklists/2026-03-24-core-matrix-kernel-manual-validation.md`

## Execution Contract

- do not start Milestone `E` work while any Milestone `D` exit criterion is
  still open
- use TDD for new behavior
- if a test or runtime path behaves unexpectedly, switch to
  `systematic-debugging` before changing implementation
- update behavior docs and the checklist in the same batch as the behavior
  change

## Batch 1: Milestone D Preflight And D1

### Task 1: Run the Milestone D preflight

**Files:**
- Review: `docs/design/2026-03-30-core-matrix-phase-2-sequential-execution-design.md`
- Review: `docs/plans/2026-03-25-core-matrix-phase-2-task-conversation-feature-policy-and-stale-work-safety.md`
- Review: `docs/plans/2026-03-25-core-matrix-phase-2-task-wait-state-human-interaction-and-subagents.md`

Run:

```bash
cd core_matrix
bin/rails test test/services/workflows/scheduler_test.rb test/services/turns/steer_current_input_test.rb test/services/human_interactions/request_test.rb test/services/subagent_sessions/spawn_test.rb test/services/runtime_capabilities/compose_for_conversation_test.rb test/services/workflows/intent_batch_materialization_test.rb test/integration/human_interaction_flow_test.rb test/integration/workflow_yield_materialization_flow_test.rb
```

Expected:

- the current baseline still matches the status refresh captured in the active
  Phase 2 docs

Stop if:

- the baseline already contradicts the D1/D2 task assumptions in a way that
  changes required behavior

### Task 2: Execute D1 with TDD

**Files:**
- Modify: `core_matrix/app/models/conversation.rb`
- Modify: `core_matrix/app/models/turn.rb`
- Modify: `core_matrix/app/models/workflow_run.rb`
- Modify: `core_matrix/app/models/agent_task_run.rb`
- Modify: `core_matrix/app/services/turns/start_user_turn.rb`
- Modify: `core_matrix/app/services/turns/start_automation_turn.rb`
- Modify: `core_matrix/app/services/turns/steer_current_input.rb`
- Modify or create: `core_matrix/app/services/conversations/*`
- Modify or create: `core_matrix/test/models/conversation_test.rb`
- Modify or create: `core_matrix/test/services/turns/feature_policy_enforcement_test.rb`
- Modify or create: `core_matrix/test/services/turns/stale_work_safety_test.rb`
- Modify or create: `core_matrix/test/integration/conversation_feature_and_stale_work_flow_test.rb`
- Modify: `core_matrix/docs/behavior/conversation-structure-and-lineage.md`
- Modify: `core_matrix/docs/behavior/turn-entry-and-selector-state.md`
- Modify: `core_matrix/docs/behavior/workflow-scheduler-and-wait-states.md`

Run first:

```bash
cd core_matrix
bin/rails test test/models/conversation_test.rb test/services/turns/feature_policy_enforcement_test.rb test/services/turns/stale_work_safety_test.rb test/integration/conversation_feature_and_stale_work_flow_test.rb
```

Expected before implementation:

- failure for the missing feature-policy or frozen-snapshot behavior

Then implement only the remaining D1 scope recorded in the task doc:

- persisted conversation feature policy
- frozen feature snapshots on active work
- disabled-feature rejection behavior
- durable stale-work safety for superseded work

Run after implementation:

```bash
cd core_matrix
bin/rails test test/models/conversation_test.rb test/services/turns/feature_policy_enforcement_test.rb test/services/turns/stale_work_safety_test.rb test/integration/conversation_feature_and_stale_work_flow_test.rb
```

Expected after implementation:

- the D1 targeted suite passes

## Batch 2: D1 Audit And D2

### Task 3: Audit D1 before continuing

**Files:**
- Review: `core_matrix/app/models/conversation.rb`
- Review: `core_matrix/app/models/turn.rb`
- Review: `core_matrix/app/models/workflow_run.rb`
- Review: `core_matrix/app/models/agent_task_run.rb`
- Review: `docs/checklists/2026-03-24-core-matrix-kernel-manual-validation.md`

Confirm:

- feature policy is conversation-owned, not controller-owned
- active-work snapshots freeze at the correct boundary
- stale-work rejection does not rely on ephemeral process-local state
- any new manual scenario introduced by D1 is reflected in the checklist

Stop if:

- D1 passes tests but the retained design boundary is obviously wrong

### Task 4: Execute D2 with TDD

**Files:**
- Modify: `core_matrix/app/services/human_interactions/request.rb`
- Modify: `core_matrix/app/services/human_interactions/submit_form.rb`
- Modify: `core_matrix/app/services/human_interactions/complete_task.rb`
- Modify: `core_matrix/app/services/subagent_sessions/spawn.rb`
- Modify: `core_matrix/app/services/workflows/manual_resume.rb`
- Modify: `core_matrix/app/services/workflows/manual_retry.rb`
- Modify: `core_matrix/app/models/human_interaction_request.rb`
- Modify: `core_matrix/app/models/subagent_session.rb`
- Modify: `core_matrix/app/models/workflow_run.rb`
- Modify: `core_matrix/app/models/workflow_node.rb`
- Modify or create: `core_matrix/test/services/human_interactions/request_test.rb`
- Modify or create: `core_matrix/test/services/human_interactions/submit_form_test.rb`
- Modify or create: `core_matrix/test/services/subagent_sessions/spawn_test.rb`
- Modify or create: `core_matrix/test/services/workflows/manual_resume_test.rb`
- Modify or create: `core_matrix/test/integration/human_interaction_and_subagent_flow_test.rb`
- Modify: `core_matrix/docs/behavior/human-interactions-and-conversation-events.md`
- Modify: `core_matrix/docs/behavior/subagent-sessions-and-execution-leases.md`
- Modify: `core_matrix/docs/behavior/workflow-scheduler-and-wait-states.md`
- Modify: `docs/checklists/2026-03-24-core-matrix-kernel-manual-validation.md`

Run first:

```bash
cd core_matrix
bin/rails test test/services/human_interactions test/services/subagent_sessions test/services/workflows/manual_resume_test.rb test/integration/human_interaction_and_subagent_flow_test.rb
```

Expected before implementation:

- failure for the missing end-to-end wait handoff or subagent resume path

Then implement only the remaining D2 scope recorded in the task doc:

- yielded runtime requests become durable workflow-owned wait transitions
- one human-interaction wait path works end to end
- one subagent path works end to end
- bounded `wait_all` subagent coordination resumes correctly

Run after implementation:

```bash
cd core_matrix
bin/rails test test/services/human_interactions test/services/subagent_sessions test/services/workflows/manual_resume_test.rb test/integration/human_interaction_and_subagent_flow_test.rb
```

Expected after implementation:

- the D2 targeted suite passes

## Batch 3: Integrated Milestone D Verification

### Task 5: Run integrated Milestone D verification

**Files:**
- Review: `docs/checklists/2026-03-24-core-matrix-kernel-manual-validation.md`
- Review: `docs/plans/2026-03-26-core-matrix-phase-2-plan-agent-loop-execution.md`

Run:

```bash
cd core_matrix
bin/rails test test/services/workflows/scheduler_test.rb test/services/turns/steer_current_input_test.rb test/services/human_interactions/request_test.rb test/services/human_interactions/submit_form_test.rb test/services/subagent_sessions/spawn_test.rb test/services/workflows/manual_resume_test.rb test/services/runtime_capabilities/compose_for_conversation_test.rb test/services/workflows/intent_batch_materialization_test.rb test/integration/human_interaction_flow_test.rb test/integration/human_interaction_and_subagent_flow_test.rb test/integration/workflow_yield_materialization_flow_test.rb
```

Expected:

- the integrated Milestone D regression set passes

### Task 6: Refresh Milestone D manual-validation entries

**Files:**
- Modify: `docs/checklists/2026-03-24-core-matrix-kernel-manual-validation.md`
- Modify: `core_matrix/docs/behavior/workflow-scheduler-and-wait-states.md`

Record or refresh exact operator sections for at least:

- during-generation `reject`, `restart`, and `queue`
- feature-disabled rejection
- human-interaction wait and resume
- subagent spawn and `wait_all` barrier re-entry

Expected:

- the checklist is ready to be executed later without inventing new operator
  steps

## Milestone D Exit Criteria

- D1 and D2 targeted tests pass
- integrated Milestone D regression set passes
- retained behavior docs are updated
- the manual checklist contains exact Milestone D real-run paths
- no unresolved blocker remains for Milestone `E`

## Must-Stop Conditions

- feature policy can only be expressed in a way that leaks internal numeric ids
- wait handoff requires private runtime-only state instead of workflow-owned
  durable state
- subagent orchestration would need a second parallel lineage outside the
  existing workflow graph
