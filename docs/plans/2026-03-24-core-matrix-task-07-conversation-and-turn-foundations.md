# Core Matrix Task 07: Rebuild Conversation Tree, Turn Core, And Variant Selection

Part of `Core Matrix Kernel Phase 3: Conversation And Runtime`.

Use this task document together with:

1. `AGENTS.md`
2. `docs/plans/2026-03-24-core-matrix-kernel-greenfield-design.md`
3. `docs/plans/2026-03-24-core-matrix-kernel-greenfield-implementation-plan.md`
4. `docs/plans/2026-03-24-core-matrix-kernel-phase-3-conversation-and-runtime.md`
5. `docs/plans/2026-03-24-core-matrix-kernel-ui-follow-up.md`
6. `docs/checklists/2026-03-24-core-matrix-kernel-manual-validation.md`

Load this file as the detailed execution unit for Task 07. Treat the phase file as the ordering index, not the full task body.

---


**Files:**
- Create: `core_matrix/db/migrate/20260324090019_create_conversations.rb`
- Create: `core_matrix/db/migrate/20260324090020_create_conversation_closures.rb`
- Create: `core_matrix/db/migrate/20260324090021_create_turns.rb`
- Create: `core_matrix/db/migrate/20260324090022_create_messages.rb`
- Create: `core_matrix/db/migrate/20260324090023_add_turn_message_foreign_keys.rb`
- Create: `core_matrix/app/models/conversation.rb`
- Create: `core_matrix/app/models/conversation_closure.rb`
- Create: `core_matrix/app/models/turn.rb`
- Create: `core_matrix/app/models/message.rb`
- Create: `core_matrix/app/models/user_message.rb`
- Create: `core_matrix/app/models/agent_message.rb`
- Create: `core_matrix/app/services/conversations/create_root.rb`
- Create: `core_matrix/app/services/conversations/create_automation_root.rb`
- Create: `core_matrix/app/services/conversations/create_branch.rb`
- Create: `core_matrix/app/services/conversations/create_thread.rb`
- Create: `core_matrix/app/services/conversations/create_checkpoint.rb`
- Create: `core_matrix/app/services/conversations/archive.rb`
- Create: `core_matrix/app/services/conversations/unarchive.rb`
- Create: `core_matrix/app/services/conversations/rollback_to_turn.rb`
- Create: `core_matrix/app/services/conversations/update_override.rb`
- Create: `core_matrix/app/services/turns/start_user_turn.rb`
- Create: `core_matrix/app/services/turns/start_automation_turn.rb`
- Create: `core_matrix/app/services/turns/edit_tail_input.rb`
- Create: `core_matrix/app/services/turns/queue_follow_up.rb`
- Create: `core_matrix/app/services/turns/retry_output.rb`
- Create: `core_matrix/app/services/turns/rerun_output.rb`
- Create: `core_matrix/app/services/turns/select_output_variant.rb`
- Create: `core_matrix/app/services/turns/steer_current_input.rb`
- Create: `core_matrix/test/models/conversation_test.rb`
- Create: `core_matrix/test/models/conversation_closure_test.rb`
- Create: `core_matrix/test/models/turn_test.rb`
- Create: `core_matrix/test/models/message_test.rb`
- Create: `core_matrix/test/models/user_message_test.rb`
- Create: `core_matrix/test/models/agent_message_test.rb`
- Create: `core_matrix/test/services/conversations/create_root_test.rb`
- Create: `core_matrix/test/services/conversations/create_automation_root_test.rb`
- Create: `core_matrix/test/services/conversations/create_branch_test.rb`
- Create: `core_matrix/test/services/conversations/create_thread_test.rb`
- Create: `core_matrix/test/services/conversations/create_checkpoint_test.rb`
- Create: `core_matrix/test/services/conversations/archive_test.rb`
- Create: `core_matrix/test/services/conversations/unarchive_test.rb`
- Create: `core_matrix/test/services/conversations/rollback_to_turn_test.rb`
- Create: `core_matrix/test/services/conversations/update_override_test.rb`
- Create: `core_matrix/test/services/turns/start_user_turn_test.rb`
- Create: `core_matrix/test/services/turns/start_automation_turn_test.rb`
- Create: `core_matrix/test/services/turns/edit_tail_input_test.rb`
- Create: `core_matrix/test/services/turns/queue_follow_up_test.rb`
- Create: `core_matrix/test/services/turns/retry_output_test.rb`
- Create: `core_matrix/test/services/turns/rerun_output_test.rb`
- Create: `core_matrix/test/services/turns/select_output_variant_test.rb`
- Create: `core_matrix/test/services/turns/steer_current_input_test.rb`
- Create: `core_matrix/test/integration/conversation_turn_flow_test.rb`

**Step 1: Write failing unit tests**

Cover at least:

- conversation belongs to workspace, not directly to agent
- closure-table integrity
- conversation kind rules for `root`, `branch`, `thread`, and `checkpoint`
- conversation lifecycle state rules for `active` and `archived`
- conversation purpose rules for `interactive` and `automation`
- conversation interactive selector modes `auto | explicit candidate`
- `auto` normalizing to `role:main` for the interactive path
- historical-anchor requirements for branch and checkpoint creation
- branch, thread, and checkpoint creation rejecting automation-purpose conversations
- turn sequence uniqueness within one conversation
- structured turn origin metadata for `manual_user`, `automation_schedule`, and `automation_webhook`
- queued versus active versus terminal turn states
- message role, slot, and variant semantics
- message STI restricted to transcript-bearing subclasses only
- selected input and output pointers
- tail input edit creating a new selected input variant without historical row mutation
- retry versus rerun semantics for assistant output variants
- swipe or variant selection legality for tail versus non-tail assistant output
- backtrack or rollback semantics for historical user-message editing without row mutation
- persisted conversation override payload and schema-fingerprint tracking
- interactive selector persistence independent from deployment-level internal slots
- automation conversations being root-only and rejecting ordinary user-turn entry paths
- automation-origin turns being allowed to start without a submitted transcript-bearing `UserMessage`
- steering blocked after the first side-effecting workflow node completes
- runtime pinning columns on turns for deployment, capability snapshots, and resolved model-selection snapshots

**Step 2: Write a failing integration flow test**

`conversation_turn_flow_test.rb` should cover:

- root conversation creation
- automation root conversation creation with read-only, non-interactive purpose semantics
- historical branch creation without transcript copying
- thread and checkpoint creation with correct lineage
- rejecting branch, thread, or checkpoint creation from an automation conversation
- archiving and unarchiving a conversation without mutating transcript history
- storing `auto` as the default interactive selector and allowing an explicit `provider_handle/model_ref` selector
- persisting a conversation override and freezing it onto the created turn snapshot
- starting an automation-origin turn without a transcript-bearing user message
- rejecting ordinary user-turn creation against an automation conversation
- editing the selected tail user input by creating a replacement input variant and resetting dependent output state
- editing a historical user message through rollback or fork semantics rather than in-place mutation
- active turn creation
- retrying a failed assistant output within the same turn
- rerunning a non-tail finished assistant output by auto-branching
- selecting a different tail output variant and rejecting the same action on non-tail history
- queued follow-up while another turn is active
- steering the active input before side effects

**Step 3: Run the targeted tests to confirm failure**

Run:

```bash
cd core_matrix
bin/rails test test/models/conversation_test.rb test/models/conversation_closure_test.rb test/models/turn_test.rb test/models/message_test.rb test/models/user_message_test.rb test/models/agent_message_test.rb test/services/conversations/create_root_test.rb test/services/conversations/create_automation_root_test.rb test/services/conversations/create_branch_test.rb test/services/conversations/create_thread_test.rb test/services/conversations/create_checkpoint_test.rb test/services/conversations/archive_test.rb test/services/conversations/unarchive_test.rb test/services/conversations/rollback_to_turn_test.rb test/services/conversations/update_override_test.rb test/services/turns/start_user_turn_test.rb test/services/turns/start_automation_turn_test.rb test/services/turns/edit_tail_input_test.rb test/services/turns/queue_follow_up_test.rb test/services/turns/retry_output_test.rb test/services/turns/rerun_output_test.rb test/services/turns/select_output_variant_test.rb test/services/turns/steer_current_input_test.rb test/integration/conversation_turn_flow_test.rb
```

Expected:

- missing table and model failures

**Step 4: Write migrations, models, and services**

Rules:

- no direct `conversation.agent_id` shortcut
- conversation rows must carry kind, purpose, parent lineage, optional historical anchor, and persisted override payload
- conversation rows must also carry the user-visible interactive selector in `auto | explicit candidate` form
- conversation lifecycle state must be modeled separately from kind
- `interactive` and `automation` purpose must be modeled separately from kind and lifecycle
- v1 automation conversations should be created as read-only `root` conversations and should reject ordinary user-turn entry services
- branch, thread, and checkpoint creation services should reject automation-purpose conversations in v1
- store selected input and output message pointers on the turn
- turn rows must persist structured origin metadata including `origin_kind`, `origin_payload`, `source_ref_type`, `source_ref_id`, `idempotency_key`, and `external_event_key`
- automation-origin turns may start without a transcript-bearing `UserMessage`
- keep explicit version-set semantics for input and output variants
- keep turn history append-only
- do not add a server-side unsent composer draft model in v1
- use `Message` STI only for transcript-bearing subclasses; non-transcript visible runtime state belongs in `ConversationEvent` or other runtime resources
- branch and checkpoint creation must preserve lineage without copying transcript rows
- thread creation must keep separate timeline identity and must not imply transcript cloning
- archived conversations must reject new turns and queue mutations until unarchived
- selected tail user input editing must create a new input variant and reset dependent output state, never mutate the historical row in place
- historical user-message editing must resolve through rollback or fork semantics, never direct row mutation
- retry must target failed or unfinished assistant output and create a new output variant in the same turn
- rerun must target finished assistant output; non-tail rerun auto-branches before execution
- selecting a different output variant is tail-only in the current timeline and must reject queued or in-flight variants
- pin deployment fingerprint, resolved config snapshot, and resolved model-selection snapshot on the executing turn

**Step 5: Run migrations and targeted tests**

Run:

```bash
cd core_matrix
bin/rails db:migrate
bin/rails test test/models/conversation_test.rb test/models/conversation_closure_test.rb test/models/turn_test.rb test/models/message_test.rb test/models/user_message_test.rb test/models/agent_message_test.rb test/services/conversations/create_root_test.rb test/services/conversations/create_automation_root_test.rb test/services/conversations/create_branch_test.rb test/services/conversations/create_thread_test.rb test/services/conversations/create_checkpoint_test.rb test/services/conversations/archive_test.rb test/services/conversations/unarchive_test.rb test/services/conversations/rollback_to_turn_test.rb test/services/conversations/update_override_test.rb test/services/turns/start_user_turn_test.rb test/services/turns/start_automation_turn_test.rb test/services/turns/edit_tail_input_test.rb test/services/turns/queue_follow_up_test.rb test/services/turns/retry_output_test.rb test/services/turns/rerun_output_test.rb test/services/turns/select_output_variant_test.rb test/services/turns/steer_current_input_test.rb test/integration/conversation_turn_flow_test.rb
```

Expected:

- targeted tests pass

**Step 6: Commit**

```bash
git -C .. add core_matrix/db/migrate core_matrix/app/models core_matrix/app/services/conversations core_matrix/app/services/turns core_matrix/test/models core_matrix/test/services core_matrix/test/integration core_matrix/db/schema.rb
git -C .. commit -m "feat: rebuild conversation tree and turn foundations"
```

