# Core Matrix Phase 2 Task: Enforce Conversation Feature Policy And Stale-Work Safety

Part of `Core Matrix Phase 2: Agent Loop Execution`.

Use this task document together with:

1. `AGENTS.md`
2. `docs/design/2026-03-25-core-matrix-platform-phases-and-validation-design.md`
3. `docs/design/2026-03-26-core-matrix-conversation-close-and-mailbox-control-protocol-design.md`
4. `docs/plans/2026-03-26-core-matrix-phase-2-plan-agent-loop-execution.md`
5. `docs/finished-plans/2026-03-25-core-matrix-phase-2-task-provider-backed-turn-execution.md`
6. `docs/finished-plans/2026-03-26-core-matrix-phase-2-task-turn-interrupt-and-conversation-close-semantics.md`

Load this file as the detailed execution unit for the conversation
feature-policy and stale-work task inside Phase 2.
Treat the milestone, sequencing, and provider-execution documents as ordering
indexes, not as the full task body.

Status note (`2026-03-30`):

- current code already contains during-generation `reject`, `restart`, and
  `queue` behavior plus stale queued-tail cancellation
- the remaining scope for this task is persisted conversation feature policy,
  frozen feature snapshots on active work, and disabled-feature rejection
  behavior

Reference capture for this task:

- if this task consults `references/` or external implementations, record the
  consulted source section and the retained conclusion, invariant, or intentional
  difference in this task document or another local document updated by the
  same execution unit
- when this task updates behavior docs, checklist docs, or other local docs,
  carry that conclusion into those docs instead of leaving only a bare
  reference path
- keep reference paths as index pointers only; restate the relevant behavior
  locally so this task remains understandable if the reference later drifts

---

**Files:**
- Modify: `core_matrix/app/models/conversation.rb`
- Modify: `core_matrix/app/models/turn.rb`
- Modify: `core_matrix/app/models/workflow_run.rb`
- Modify: `core_matrix/app/models/agent_task_run.rb`
- Modify: `core_matrix/app/services/turns/start_user_turn.rb`
- Modify: `core_matrix/app/services/turns/start_automation_turn.rb`
- Modify: `core_matrix/app/services/turns/steer_current_input.rb`
- Likely create or modify: `core_matrix/app/services/conversations/*`
- Create or modify: `core_matrix/test/models/conversation_test.rb`
- Create or modify: `core_matrix/test/services/turns/feature_policy_enforcement_test.rb`
- Create or modify: `core_matrix/test/services/turns/stale_work_safety_test.rb`
- Create or modify: `core_matrix/test/integration/conversation_feature_and_stale_work_flow_test.rb`
- Modify: `core_matrix/docs/behavior/conversation-structure-and-lineage.md`
- Modify: `core_matrix/docs/behavior/turn-entry-and-selector-state.md`
- Modify: `core_matrix/docs/behavior/workflow-scheduler-and-wait-states.md`

## Boundary

This task owns:

- conversation-level feature policy storage
- feature-policy snapshots on active work
- during-generation input policies such as `reject`, `restart`, and `queue`
- stale-tail ownership checks when newer input or selector movement supersedes
  older work

This task does not own:

- `turn_interrupt` fences
- archive or delete close orchestration
- `step_retry` gates
- resource-close delivery

**Step 1: Write failing model, service, and integration tests**

Cover at least:

- persisted conversation feature policy
- frozen feature-policy snapshot on running work
- deterministic rejection of disabled kernel behavior
- automation-triggered conversation with `human_interaction` disabled
- `reject`, `restart`, and `queue` semantics under new input
- safe stale-result rejection when an older attempt no longer owns the current
  tail after a newer input or selector change

**Step 2: Run the targeted tests to confirm failure**

Run:

```bash
cd core_matrix
bin/rails test test/models/conversation_test.rb test/services/turns/feature_policy_enforcement_test.rb test/services/turns/stale_work_safety_test.rb test/integration/conversation_feature_and_stale_work_flow_test.rb
```

Expected:

- missing feature-policy, snapshot, or stale-work failures

**Step 3: Implement conversation feature policy and stale-work rules**

Rules:

- breaking changes are allowed in Phase 2
- feature gating is kernel execution behavior, not UI-only configuration
- stale-work protection must be durable and auditable
- `reject`, `restart`, and `queue` must stay authoritative at the kernel level
- older superseded work must not commit transcript-affecting output as if it
  were current
- rely on the mailbox and interrupt model from the close-semantics task rather
  than redefining close fences here

Prove the initial feature set:

- `human_interaction`
- `tool_invocation`
- `message_attachments`
- `conversation_branching`
- `conversation_archival`

**Step 4: Update local behavior docs**

Document exact retained behavior for:

- conversation feature policy storage and snapshots
- disabled-feature rejection behavior
- stale-tail protection
- during-generation input policy enforcement

**Step 5: Run the targeted tests**

Run:

```bash
cd core_matrix
bin/rails test test/models/conversation_test.rb test/services/turns/feature_policy_enforcement_test.rb test/services/turns/stale_work_safety_test.rb test/integration/conversation_feature_and_stale_work_flow_test.rb
```

Expected:

- targeted feature-policy and stale-work tests pass

**Step 6: Commit**

```bash
git -C .. add core_matrix/app/models/conversation.rb core_matrix/app/models/turn.rb core_matrix/app/models/workflow_run.rb core_matrix/app/models/agent_task_run.rb core_matrix/app/services/turns/start_user_turn.rb core_matrix/app/services/turns/start_automation_turn.rb core_matrix/app/services/turns/steer_current_input.rb core_matrix/app/services/conversations core_matrix/test/models/conversation_test.rb core_matrix/test/services/turns/feature_policy_enforcement_test.rb core_matrix/test/services/turns/stale_work_safety_test.rb core_matrix/test/integration/conversation_feature_and_stale_work_flow_test.rb core_matrix/docs/behavior/conversation-structure-and-lineage.md core_matrix/docs/behavior/turn-entry-and-selector-state.md core_matrix/docs/behavior/workflow-scheduler-and-wait-states.md
git -C .. commit -m "feat: enforce conversation feature policy"
```

## Stop Point

Stop after feature policy and stale-work safety are durable kernel behavior.

Do not implement these items in this task:

- human-interaction wait handoff
- subagent orchestration
- `step_retry` workflow gates
- turn interrupt fences
- archive or delete close orchestration
- broad tool governance
- Streamable HTTP MCP
- `Fenix` runtime or skills
