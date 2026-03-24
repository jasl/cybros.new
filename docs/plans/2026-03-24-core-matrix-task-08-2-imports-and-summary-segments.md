# Core Matrix Task 08.2: Add Imports And Summary Segments

Part of `Core Matrix Kernel Milestone 3: Conversation And Runtime`.

Use this task document together with:

1. `AGENTS.md`
2. `docs/design/2026-03-24-core-matrix-kernel-greenfield-design.md`
3. `docs/plans/2026-03-24-core-matrix-kernel-greenfield-implementation-plan.md`
4. `docs/plans/2026-03-24-core-matrix-kernel-milestone-3-conversation-and-runtime.md`

Load this file as the detailed execution unit for Task 08.2. Treat Task Group 08 and the milestone file as ordering indexes, not as the full task body.

Reference capture for this task:

- if this task consults `references/` or external implementations, record the consulted slice and the retained conclusion, invariant, or intentional difference in this task document or another local document updated by the same execution unit
- when this task updates behavior docs, checklist docs, or other local docs, carry that conclusion into those docs instead of leaving only a bare reference path
- keep reference paths as index pointers only; restate the relevant behavior locally so this task remains understandable if the reference later drifts

---

**Files:**
- Create: `core_matrix/db/migrate/20260324090026_create_conversation_imports.rb`
- Create: `core_matrix/db/migrate/20260324090027_create_conversation_summary_segments.rb`
- Create: `core_matrix/app/models/conversation_import.rb`
- Create: `core_matrix/app/models/conversation_summary_segment.rb`
- Create: `core_matrix/app/services/conversations/add_import.rb`
- Create: `core_matrix/app/services/conversation_summaries/create_segment.rb`
- Create: `core_matrix/test/models/conversation_import_test.rb`
- Create: `core_matrix/test/models/conversation_summary_segment_test.rb`
- Create: `core_matrix/test/services/conversations/add_import_test.rb`
- Create: `core_matrix/test/services/conversation_summaries/create_segment_test.rb`
- Create: `core_matrix/test/integration/transcript_import_summary_flow_test.rb`
- Modify: `core_matrix/app/services/conversations/rollback_to_turn.rb`
- Modify: `core_matrix/test/services/conversations/rollback_to_turn_test.rb`

**Step 1: Write failing model, service, and integration tests**

Cover at least:

- import kinds `branch_prefix`, `merge_summary`, and `quoted_context`
- summary segment replacement and supersession
- branching from a historical message and creating a `branch_prefix` import
- creating a summary segment and importing it back as context
- rollback behind a compaction boundary preserving earlier compacted history and dropping only superseded post-rollback state
- fork-point protection for soft delete and other rewriting operations
- never copying full transcript history into branch conversations

**Step 2: Run the targeted tests to confirm failure**

Run:

```bash
cd core_matrix
bin/rails test test/models/conversation_import_test.rb test/models/conversation_summary_segment_test.rb test/services/conversations/add_import_test.rb test/services/conversation_summaries/create_segment_test.rb test/services/conversations/rollback_to_turn_test.rb test/integration/transcript_import_summary_flow_test.rb
```

Expected:

- missing table and model failures

**Step 3: Write migrations, models, and services**

Rules:

- keep transcript rows immutable
- rollback must preserve valid summary segments or imports that still describe retained history while dropping superseded post-rollback context
- fork-point messages are not soft-deletable or otherwise rewritable
- never copy full transcript history into branch conversations

**Step 4: Run migrations and targeted tests**

Run:

```bash
cd core_matrix
bin/rails db:migrate
bin/rails test test/models/conversation_import_test.rb test/models/conversation_summary_segment_test.rb test/services/conversations/add_import_test.rb test/services/conversation_summaries/create_segment_test.rb test/services/conversations/rollback_to_turn_test.rb test/integration/transcript_import_summary_flow_test.rb
```

Expected:

- targeted tests pass

**Step 5: Commit**

```bash
git -C .. add core_matrix/db/migrate core_matrix/app/models/conversation_import.rb core_matrix/app/models/conversation_summary_segment.rb core_matrix/app/services/conversations/add_import.rb core_matrix/app/services/conversation_summaries core_matrix/app/services/conversations/rollback_to_turn.rb core_matrix/test/models core_matrix/test/services core_matrix/test/integration core_matrix/db/schema.rb
git -C .. commit -m "feat: add transcript imports and summary segments"
```

## Stop Point

Stop after imports, summary segments, and compaction-boundary semantics pass their tests.

Do not implement these items in this task:

- human-facing transcript compaction UI
- publication rendering
- workflow context assembly logic from Task 09
