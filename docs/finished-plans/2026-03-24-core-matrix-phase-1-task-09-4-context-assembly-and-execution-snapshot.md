# Core Matrix Task 09.4: Add Context Assembly And Execution Snapshot

Part of `Core Matrix Kernel Milestone 3: Conversation And Runtime`.

Use this task document together with:

1. `AGENTS.md`
2. `docs/design/2026-03-24-core-matrix-kernel-greenfield-design.md`
3. `docs/finished-plans/2026-03-24-core-matrix-phase-1-kernel-greenfield-implementation-plan.md`
4. `docs/finished-plans/2026-03-24-core-matrix-phase-1-kernel-milestone-3-conversation-and-runtime.md`
5. `docs/design/2026-03-24-core-matrix-model-role-resolution-design.md`

Load this file as the detailed execution unit for Task 09.4. Treat Task Group 09 and the milestone file as ordering indexes, not as the full task body.

Reference capture for this task:

- if this task consults `references/` or external implementations, record the consulted slice and the retained conclusion, invariant, or intentional difference in this task document or another local document updated by the same execution unit
- when this task updates behavior docs, checklist docs, or other local docs, carry that conclusion into those docs instead of leaving only a bare reference path
- keep reference paths as index pointers only; restate the relevant behavior locally so this task remains understandable if the reference later drifts

---

**Files:**
- Create: `core_matrix/app/services/workflows/context_assembler.rb`
- Create: `core_matrix/test/services/workflows/context_assembler_test.rb`
- Create: `core_matrix/test/integration/workflow_context_flow_test.rb`
- Modify: `core_matrix/app/models/turn.rb`
- Modify: `core_matrix/app/models/workflow_run.rb`
- Modify: `core_matrix/app/services/workflows/create_for_turn.rb`
- Modify: `core_matrix/test/models/turn_test.rb`
- Modify: `core_matrix/test/services/workflows/create_for_turn_test.rb`

**Step 1: Write failing service and integration tests**

Cover at least:

- context assembly from base rules, active imports, transcript tail, selected workflow outputs, and eligible attachment manifests
- context assembly for automation-origin turns without a transcript-bearing user input
- execution-context identity fields for agent code, including `user_id`, `workspace_id`, `conversation_id`, and `turn_id`
- capability-gated attachment prompt projection based on the turn's pinned provider or model snapshot
- hidden, excluded, or branch-ineligible attachments never appearing in runtime manifests or model input blocks
- unsupported attachments remaining available to runtime preparation without being serialized as if the model received them
- non-transcript `ConversationEvent` rows never entering canonical transcript context assembly by default
- assembling context that includes imports and summary artifacts without walking a global conversation DAG

**Step 2: Run the targeted tests to confirm failure**

Run:

```bash
cd core_matrix
bin/rails test test/models/turn_test.rb test/services/workflows/create_for_turn_test.rb test/services/workflows/context_assembler_test.rb test/integration/workflow_context_flow_test.rb
```

Expected:

- missing service or context-assembly failures

**Step 3: Implement context assembly**

Rules:

- context assembly must not depend on a global conversation DAG
- context assembly must tolerate automation-origin turns that begin from trigger metadata or workflow bootstrap state instead of a transcript-bearing user message
- context assembly must freeze a canonical attachment manifest on the executing turn as the canonical execution snapshot and derive both runtime and model-facing projections from it, with optional denormalized references on `WorkflowRun`
- attachment prompt projection must be capability-gated by pinned catalog metadata rather than the latest mutable catalog state
- context assembly must record explicit diagnostic events when attachment preparation or prompt projection is skipped or degraded
- context assembly must draw from transcript-bearing messages and approved support rows, not from `ConversationEvent` projections by default
- context assembly must expose stable ownership identity fields so agent code can reason about the current user, workspace, conversation, and turn without scraping transcript text

**Step 4: Run the targeted tests**

Run:

```bash
cd core_matrix
bin/rails test test/models/turn_test.rb test/services/workflows/create_for_turn_test.rb test/services/workflows/context_assembler_test.rb test/integration/workflow_context_flow_test.rb
```

Expected:

- targeted tests pass

**Step 5: Commit**

```bash
git -C .. add core_matrix/app/models/turn.rb core_matrix/app/models/workflow_run.rb core_matrix/app/services/workflows/context_assembler.rb core_matrix/app/services/workflows/create_for_turn.rb core_matrix/test/models core_matrix/test/services core_matrix/test/integration
git -C .. commit -m "feat: add workflow context assembly"
```

## Stop Point

Stop after context assembly and execution snapshot projection pass their tests.

Do not implement these items in this task:

- workflow-node side-effect execution
- machine-facing protocol controllers
- publication rendering

## Completion Record

- status:
  completed on `2026-03-25`
- landing commit:
  - included in the accompanying `feat: add workflow context assembly` task
    commit
- actual landed scope:
  - added `Workflows::ContextAssembler` to freeze wrapped execution snapshots on
    `Turn.resolved_config_snapshot`
  - extended `Turn` with helpers for effective config, execution identity,
    origin context, context messages, imports, attachment manifest, runtime
    attachment manifest, model input attachments, and attachment diagnostics
  - extended `WorkflowRun` with delegated execution-identity and attachment
    projection helpers sourced from the owning turn
  - updated `Workflows::CreateForTurn` so selector resolution is followed by
    context assembly before the workflow run row is created
  - added targeted service and integration coverage for transcript-tail context
    assembly, automation turns without selected input messages, local import and
    summary inclusion, branch-ineligible attachment exclusion, runtime-only
    unsupported attachments, and preserved execution identity
  - added `core_matrix/docs/behavior/workflow-context-assembly-and-execution-snapshot.md`
- plan alignment notes:
  - context assembly remains bounded to the current conversation projection and
    local import rows; it does not walk a global conversation DAG
  - the canonical attachment store is now a frozen per-turn manifest, with
    runtime and model-facing projections derived from it
  - unsupported attachments remain available to runtime tooling but are not
    serialized as if the model consumed them
  - automation-origin turns now preserve trigger metadata in the execution
    snapshot instead of assuming a user input message exists
- verification evidence:
  - `cd core_matrix && bin/rails test test/models/turn_test.rb test/services/workflows/create_for_turn_test.rb test/services/workflows/context_assembler_test.rb test/integration/workflow_context_flow_test.rb`
    passed with `9 runs, 56 assertions, 0 failures, 0 errors`
- checklist notes:
  - no manual-checklist delta was retained for this task because the landed
    behavior is execution snapshot projection and attachment gating covered by
    automated tests
- retained findings:
  - without a new schema surface, the cleanest v1 fit was to wrap
    `resolved_config_snapshot` into `{ config, execution_context }` so config
    state stays distinguishable from assembled runtime context
  - branch eligibility and visibility rules were already encoded in
    `Conversation#context_projection_messages`, so 09.4 could reuse that local
    projection instead of inventing a second attachment-visibility algorithm
  - context assembly needs explicit diagnostics for unsupported modalities even
    when runtime tooling may still use the attachment
  - Dify was useful as a sanity check for separating file prompt injection from
    current workflow rendering, but Core Matrix keeps the stronger local rule
    that a canonical attachment manifest is frozen before runtime and model
    projections are derived
- carry-forward notes:
  - later runtime event-stream work should project `attachment_diagnostics` into
    workflow-node or conversation-visible event rows without changing the frozen
    execution snapshot
  - future protocol-controller tasks should expose the same execution identity
    and runtime attachment refs already frozen here, rather than recomputing
    them ad hoc from live conversation state
