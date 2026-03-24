# Core Matrix Task 08: Add Transcript Support Models For Attachments, Imports, Summaries, And Visibility

Part of `Core Matrix Kernel Phase 3: Conversation And Runtime`.

Use this task document together with:

1. `AGENTS.md`
2. `docs/plans/2026-03-24-core-matrix-kernel-greenfield-design.md`
3. `docs/plans/2026-03-24-core-matrix-kernel-greenfield-implementation-plan.md`
4. `docs/plans/2026-03-24-core-matrix-kernel-phase-3-conversation-and-runtime.md`
5. `docs/plans/2026-03-24-core-matrix-kernel-ui-follow-up.md`
6. `docs/checklists/2026-03-24-core-matrix-kernel-manual-validation.md`

Load this file as the detailed execution unit for Task 08. Treat the phase file as the ordering index, not the full task body.

---


**Files:**
- Create: `core_matrix/db/migrate/20260324090024_create_conversation_message_visibilities.rb`
- Create: `core_matrix/db/migrate/20260324090025_create_message_attachments.rb`
- Create: `core_matrix/db/migrate/20260324090026_create_conversation_imports.rb`
- Create: `core_matrix/db/migrate/20260324090027_create_conversation_summary_segments.rb`
- Create: `core_matrix/app/models/conversation_message_visibility.rb`
- Create: `core_matrix/app/models/message_attachment.rb`
- Create: `core_matrix/app/models/conversation_import.rb`
- Create: `core_matrix/app/models/conversation_summary_segment.rb`
- Create: `core_matrix/app/services/messages/update_visibility.rb`
- Create: `core_matrix/app/services/attachments/materialize_refs.rb`
- Create: `core_matrix/app/services/conversations/add_import.rb`
- Create: `core_matrix/app/services/conversation_summaries/create_segment.rb`
- Create: `core_matrix/test/models/conversation_message_visibility_test.rb`
- Create: `core_matrix/test/models/message_attachment_test.rb`
- Create: `core_matrix/test/models/conversation_import_test.rb`
- Create: `core_matrix/test/models/conversation_summary_segment_test.rb`
- Create: `core_matrix/test/services/messages/update_visibility_test.rb`
- Create: `core_matrix/test/services/attachments/materialize_refs_test.rb`
- Create: `core_matrix/test/services/conversations/add_import_test.rb`
- Create: `core_matrix/test/services/conversation_summaries/create_segment_test.rb`
- Create: `core_matrix/test/integration/transcript_support_flow_test.rb`

**Step 1: Write failing unit tests**

Cover at least:

- soft delete and context exclusion through overlay rows
- attachment ancestry and origin pointers
- attachment visibility inheriting from the parent message instead of a separate attachment overlay model
- import kinds `branch_prefix`, `merge_summary`, and `quoted_context`
- summary segment replacement and supersession
- rollback behind a compaction boundary preserving earlier compacted history and dropping only superseded post-rollback state
- fork-point protection for soft delete and other rewriting operations
- Active Storage attachment presence for file-bearing attachment rows

**Step 2: Write a failing integration flow test**

`transcript_support_flow_test.rb` should cover:

- branching from a historical message and creating a `branch_prefix` import
- creating a checkpoint view of history without leaking hidden messages
- materializing reusable attachment references into a new turn
- confirming hidden or excluded message attachments do not appear in checkpoint or branch-derived transcript support projections
- creating a summary segment and importing it back as context
- rolling back behind a summary compaction without losing preserved earlier context
- excluding a message from context without deleting the immutable message row

**Step 3: Run the targeted tests to confirm failure**

Run:

```bash
cd core_matrix
bin/rails test test/models/conversation_message_visibility_test.rb test/models/message_attachment_test.rb test/models/conversation_import_test.rb test/models/conversation_summary_segment_test.rb test/services/messages/update_visibility_test.rb test/services/attachments/materialize_refs_test.rb test/services/conversations/add_import_test.rb test/services/conversation_summaries/create_segment_test.rb test/integration/transcript_support_flow_test.rb
```

Expected:

- missing table and model failures

**Step 4: Write migrations, models, and services**

Rules:

- keep transcript rows immutable
- use overlay rows for mutable visibility
- use `has_one_attached` on `MessageAttachment`
- keep attachment visibility and context inclusion derived from the parent message in v1
- hidden transcript content must stay out of branch and checkpoint replay surfaces
- rollback must preserve valid summary segments or imports that still describe retained history while dropping superseded post-rollback context
- fork-point messages are not soft-deletable or otherwise rewritable
- never copy full transcript history into branch conversations

**Step 5: Run migrations and targeted tests**

Run:

```bash
cd core_matrix
bin/rails db:migrate
bin/rails test test/models/conversation_message_visibility_test.rb test/models/message_attachment_test.rb test/models/conversation_import_test.rb test/models/conversation_summary_segment_test.rb test/services/messages/update_visibility_test.rb test/services/attachments/materialize_refs_test.rb test/services/conversations/add_import_test.rb test/services/conversation_summaries/create_segment_test.rb test/integration/transcript_support_flow_test.rb
```

Expected:

- targeted tests pass

**Step 6: Commit**

```bash
git -C .. add core_matrix/db/migrate core_matrix/app/models core_matrix/app/services/messages core_matrix/app/services/attachments core_matrix/app/services/conversations core_matrix/app/services/conversation_summaries core_matrix/test/models core_matrix/test/services core_matrix/test/integration core_matrix/db/schema.rb
git -C .. commit -m "feat: add transcript support models"
```

