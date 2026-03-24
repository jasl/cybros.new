# Core Matrix Task 07.2: Build Turn Entry And Override State

Part of `Core Matrix Kernel Phase 3: Conversation And Runtime`.

Use this task document together with:

1. `AGENTS.md`
2. `docs/plans/2026-03-24-core-matrix-kernel-greenfield-design.md`
3. `docs/plans/2026-03-24-core-matrix-kernel-greenfield-implementation-plan.md`
4. `docs/plans/2026-03-24-core-matrix-kernel-phase-3-conversation-and-runtime.md`
5. `docs/plans/2026-03-24-core-matrix-model-role-resolution-design.md`

Load this file as the detailed execution unit for Task 07.2. Treat Task 07 and the phase file as ordering indexes, not as the full task body.

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
- do not resolve provider fallback or entitlement exhaustion behavior in this subtask; persist only the selector and the turn snapshot inputs needed by Task 09
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

Do not implement these items in this subtask:

- selector fallback resolution or entitlement reservation
- rollback, historical edit, retry, rerun, or output-variant selection
- workflow-node-aware steering beyond the pre-execution state needed for this task
