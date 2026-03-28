# Core Matrix Phase 2 Task: Add Wait-State Handoff, Human Interaction, And Subagents

Part of `Core Matrix Phase 2: Agent Loop Execution`.

Use this task document together with:

1. `AGENTS.md`
2. `docs/design/2026-03-25-core-matrix-workflow-yield-and-intent-batch-design.md`
3. `docs/plans/2026-03-26-core-matrix-phase-2-plan-agent-loop-execution.md`
4. `docs/plans/2026-03-25-core-matrix-phase-2-task-conversation-feature-policy-and-stale-work-safety.md`
5. `docs/plans/2026-03-26-core-matrix-phase-2-task-mailbox-control-and-resource-close-contract.md`
6. `docs/plans/2026-03-26-core-matrix-phase-2-task-turn-interrupt-and-conversation-close-semantics.md`

Load this file as the detailed execution unit for the wait-state, human
interaction, and subagents task inside Phase 2.
Treat the milestone, sequencing, and preceding task documents as ordering
indexes, not as the full task body.

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
- Create or modify: `core_matrix/test/services/human_interactions/request_test.rb`
- Create or modify: `core_matrix/test/services/human_interactions/submit_form_test.rb`
- Create or modify: `core_matrix/test/services/subagent_sessions/spawn_test.rb`
- Create or modify: `core_matrix/test/services/workflows/manual_resume_test.rb`
- Create or modify: `core_matrix/test/integration/human_interaction_and_subagent_flow_test.rb`
- Modify: `core_matrix/docs/behavior/human-interactions-and-conversation-events.md`
- Modify: `core_matrix/docs/behavior/subagent-runs-and-execution-leases.md`
- Modify: `core_matrix/docs/behavior/workflow-scheduler-and-wait-states.md`

**Step 1: Write failing service and integration tests**

Cover at least:

- canonical wait handoff through a payload such as
  `wait_transition_requested`
- one `HumanFormRequest` or `HumanTaskRequest` path
- one `SubagentSession` path
- workflow wait-state entry and exit for both
- successor `AgentTaskRun` re-entry after wait resolution
- bounded parallel subagent spawn under `completion_barrier = wait_all`

**Step 2: Run the targeted tests to confirm failure**

Run:

```bash
cd core_matrix
bin/rails test test/services/human_interactions test/services/subagent_sessions test/services/workflows/manual_resume_test.rb test/integration/human_interaction_and_subagent_flow_test.rb
```

Expected:

- missing wait-handoff, resume, or subagent-flow failures

**Step 3: Implement kernel-owned wait and resume semantics**

Rules:

- breaking changes are allowed in Phase 2
- runtime execution must request wait; it must not silently pause in private
  runtime state
- human interaction and subagent coordination are workflow-owned runtime
  resources
- resume behavior should re-enter the agent with a fresh snapshot rather than
  continuing stale execution in place
- Phase 2 parallel intent stages are limited to approved bounded cases such as
  subagent spawn under `wait_all`

**Step 4: Update local behavior docs**

Document exact retained behavior for:

- wait-transition handoff
- human-interaction lifecycle
- subagent lifecycle
- resume and retry semantics after wait

**Step 5: Run the targeted tests**

Run:

```bash
cd core_matrix
bin/rails test test/services/human_interactions test/services/subagent_sessions test/services/workflows/manual_resume_test.rb test/integration/human_interaction_and_subagent_flow_test.rb
```

Expected:

- targeted wait-state and subagent tests pass

**Step 6: Commit**

```bash
git -C .. add core_matrix/app/services/human_interactions core_matrix/app/services/subagent_sessions core_matrix/app/services/workflows/manual_resume.rb core_matrix/app/services/workflows/manual_retry.rb core_matrix/app/models/human_interaction_request.rb core_matrix/app/models/subagent_session.rb core_matrix/app/models/workflow_run.rb core_matrix/app/models/workflow_node.rb core_matrix/test/services/human_interactions core_matrix/test/services/subagent_sessions core_matrix/test/services/workflows/manual_resume_test.rb core_matrix/test/integration/human_interaction_and_subagent_flow_test.rb core_matrix/docs/behavior/human-interactions-and-conversation-events.md core_matrix/docs/behavior/subagent-runs-and-execution-leases.md core_matrix/docs/behavior/workflow-scheduler-and-wait-states.md
git -C .. commit -m "feat: add workflow wait-state handoff"
```

## Stop Point

Stop after real wait-state handoff, human interaction, and subagent execution
work through kernel-owned workflow semantics.

Do not implement these items in this task:

- broad tool governance
- Streamable HTTP MCP
- `Fenix` runtime surface
- skill installation
