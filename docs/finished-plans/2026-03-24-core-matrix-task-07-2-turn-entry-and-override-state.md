# Core Matrix Task 07.2: Build Turn Entry And Override State

Part of `Core Matrix Kernel Milestone 3: Conversation And Runtime`.

Use this task document together with:

1. `AGENTS.md`
2. `docs/design/2026-03-24-core-matrix-kernel-greenfield-design.md`
3. `docs/finished-plans/2026-03-24-core-matrix-kernel-greenfield-implementation-plan.md`
4. `docs/finished-plans/2026-03-24-core-matrix-kernel-milestone-3-conversation-and-runtime.md`
5. `docs/design/2026-03-24-core-matrix-model-role-resolution-design.md`

Load this file as the detailed execution unit for Task 07.2. Treat Task Group 07 and the milestone file as ordering indexes, not as the full task body.

Reference capture for this task:

- if this task consults `references/` or external implementations, record the consulted slice and the retained conclusion, invariant, or intentional difference in this task document or another local document updated by the same execution unit
- when this task updates behavior docs, checklist docs, or other local docs, carry that conclusion into those docs instead of leaving only a bare reference path
- keep reference paths as index pointers only; restate the relevant behavior locally so this task remains understandable if the reference later drifts

---

**Files:**
- Create: `core_matrix/db/migrate/20260324090021_create_turns.rb`
- Create: `core_matrix/db/migrate/20260324090022_create_messages.rb`
- Create: `core_matrix/db/migrate/20260324090023_add_turn_message_foreign_keys.rb`
- Create: `core_matrix/app/models/turn.rb`
- Create: `core_matrix/app/models/message.rb`
- Create: `core_matrix/app/models/user_message.rb`
- Create: `core_matrix/app/models/agent_message.rb`
- Create: `core_matrix/app/services/conversations/update_override.rb`
- Create: `core_matrix/app/services/turns/start_user_turn.rb`
- Create: `core_matrix/app/services/turns/start_automation_turn.rb`
- Create: `core_matrix/app/services/turns/queue_follow_up.rb`
- Create: `core_matrix/app/services/turns/steer_current_input.rb`
- Create: `core_matrix/test/models/turn_test.rb`
- Create: `core_matrix/test/models/message_test.rb`
- Create: `core_matrix/test/models/user_message_test.rb`
- Create: `core_matrix/test/models/agent_message_test.rb`
- Create: `core_matrix/test/services/conversations/update_override_test.rb`
- Create: `core_matrix/test/services/turns/start_user_turn_test.rb`
- Create: `core_matrix/test/services/turns/start_automation_turn_test.rb`
- Create: `core_matrix/test/services/turns/queue_follow_up_test.rb`
- Create: `core_matrix/test/services/turns/steer_current_input_test.rb`
- Create: `core_matrix/test/integration/turn_entry_flow_test.rb`

**Step 1: Write failing model, service, and integration tests**

Cover at least:

- turn sequence uniqueness within one conversation
- structured turn origin metadata for `manual_user`, `automation_schedule`, and `automation_webhook`
- queued versus active versus terminal turn states
- message role, slot, and variant semantics
- message STI restricted to transcript-bearing subclasses only
- selected input and output pointers
- persisted conversation override payload and schema-fingerprint tracking
- conversation interactive selector modes `auto | explicit candidate`
- automation conversations rejecting ordinary user-turn entry
- automation-origin turns being allowed to start without a transcript-bearing `UserMessage`

**Step 2: Run the targeted tests to confirm failure**

Run:

```bash
cd core_matrix
bin/rails test test/models/turn_test.rb test/models/message_test.rb test/models/user_message_test.rb test/models/agent_message_test.rb test/services/conversations/update_override_test.rb test/services/turns/start_user_turn_test.rb test/services/turns/start_automation_turn_test.rb test/services/turns/queue_follow_up_test.rb test/services/turns/steer_current_input_test.rb test/integration/turn_entry_flow_test.rb
```

Expected:

- missing table, model, or service failures

**Step 3: Write migrations, models, and services**

Rules:

- conversation rows must store the user-visible interactive selector in `auto | explicit candidate` form
- do not resolve provider fallback or entitlement exhaustion behavior in this task; persist only the selector and the turn snapshot inputs needed by Task 09
- store selected input and output message pointers on the turn
- turn rows must persist structured origin metadata including `origin_kind`, `origin_payload`, `source_ref_type`, `source_ref_id`, `idempotency_key`, and `external_event_key`
- automation-origin turns may start without a transcript-bearing `UserMessage`
- ordinary user-turn entry must reject automation-purpose conversations
- persist conversation override payload separately from deployment-level slots
- pin deployment fingerprint, resolved config snapshot, and resolved model-selection snapshot on the executing turn
- keep turn history append-only and do not add a server-side unsent composer draft model in v1

**Step 4: Run migrations and targeted tests**

Run:

```bash
cd core_matrix
bin/rails db:migrate
bin/rails test test/models/turn_test.rb test/models/message_test.rb test/models/user_message_test.rb test/models/agent_message_test.rb test/services/conversations/update_override_test.rb test/services/turns/start_user_turn_test.rb test/services/turns/start_automation_turn_test.rb test/services/turns/queue_follow_up_test.rb test/services/turns/steer_current_input_test.rb test/integration/turn_entry_flow_test.rb
```

Expected:

- targeted tests pass

**Step 5: Commit**

```bash
git -C .. add core_matrix/db/migrate core_matrix/app/models/turn.rb core_matrix/app/models/message.rb core_matrix/app/models/user_message.rb core_matrix/app/models/agent_message.rb core_matrix/app/services/conversations/update_override.rb core_matrix/app/services/turns core_matrix/test/models core_matrix/test/services core_matrix/test/integration core_matrix/db/schema.rb
git -C .. commit -m "feat: add turn entry and selector state"
```

## Stop Point

Stop after turn entry, selector persistence, override persistence, and queued-turn state pass their tests.

Do not implement these items in this task:

- selector fallback resolution or entitlement reservation
- rollback, historical edit, retry, rerun, or output-variant selection
- workflow-node-aware steering beyond the pre-execution state needed for this task

## Completion Record

- status:
  completed on `2026-03-24`
- actual landed scope:
  - added `Turn`, `Message`, `UserMessage`, and `AgentMessage` persistence
  - added conversation selector and override columns on `Conversation`
  - added `Conversations::UpdateOverride`
  - added `Turns::StartUserTurn`, `StartAutomationTurn`, `QueueFollowUp`, and
    `SteerCurrentInput`
  - added `core_matrix/docs/behavior/turn-entry-and-selector-state.md`
  - added targeted model, service, and integration coverage for turn origin
    metadata, selector persistence, override persistence, queued follow-up
    semantics, selected transcript pointers, and transcript-bearing STI rules
- plan alignment notes:
  - the task persisted only conversation selector input and turn snapshot state;
    it did not implement selector resolution, fallback, or entitlement
    reservation
  - automation-origin turns were allowed to start without a transcript-bearing
    `UserMessage`, while ordinary user entry into automation conversations was
    rejected
  - queued follow-up behavior was bounded to conversations that already have
    active or queued work
- verification evidence:
  - `cd core_matrix && bin/rails test test/models/turn_test.rb test/models/message_test.rb test/models/user_message_test.rb test/models/agent_message_test.rb test/services/conversations/update_override_test.rb test/services/turns/start_user_turn_test.rb test/services/turns/start_automation_turn_test.rb test/services/turns/queue_follow_up_test.rb test/services/turns/steer_current_input_test.rb test/integration/turn_entry_flow_test.rb`
    passed with `15 runs, 66 assertions, 0 failures, 0 errors`
- checklist notes:
  - no manual checklist delta was retained for this task because the landed
    behavior is structural runtime state covered by automated tests
- retained findings:
  - conversation selector persistence is clearer when expressed as `auto` or
    one explicit candidate, rather than prematurely storing normalized or
    fallback-expanded forms
  - selected input and output pointers belong on the turn as explicit runtime
    state instead of being inferred from latest-message heuristics
  - queued follow-up needs an active-work guard to avoid stranded queued turns
- carry-forward notes:
  - Task 07.3 should treat input and output variants as append-only rows and
    reuse the selected-pointer structure introduced here
  - Task 09.3 should consume the persisted selector and frozen turn snapshot
    fields without mutating the conversation selector during resolution
