# Core Matrix Task 08.2: Add Imports And Summary Segments

Part of `Core Matrix Kernel Milestone 3: Conversation And Runtime`.

Use this task document together with:

1. `AGENTS.md`
2. `docs/design/2026-03-24-core-matrix-kernel-greenfield-design.md`
3. `docs/finished-plans/2026-03-24-core-matrix-phase-1-kernel-greenfield-implementation-plan.md`
4. `docs/finished-plans/2026-03-24-core-matrix-phase-1-kernel-milestone-3-conversation-and-runtime.md`

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

## Completion Record

- status:
  completed on `2026-03-25`
- actual landed scope:
  - added `ConversationImport` with `branch_prefix`, `merge_summary`, and
    `quoted_context`
  - added `ConversationSummarySegment` with explicit `superseded_by` replacement
    links
  - added `Conversations::AddImport` and
    `ConversationSummaries::CreateSegment`
  - extended `Conversations::CreateBranch` to materialize a `branch_prefix`
    import when the anchor resolves to a real message row
  - extended `Conversations::RollbackToTurn` to preserve retained compacted
    history while dropping superseded post-rollback support state
  - tightened fork-point protection across visibility overlays and in-place tail
    rewrite operations
  - added `core_matrix/docs/behavior/transcript-imports-and-summary-segments.md`
    and aligned the existing rewrite and visibility behavior docs
  - added targeted model, service, rollback, and integration coverage for
    import kinds, summary supersession, compaction-boundary cleanup, branch
    prefixes, and fork-point protection
- plan alignment notes:
  - branch conversations now carry historical prefix provenance by import row
    instead of transcript-copy semantics
  - summary replacement stayed append-only by using supersession pointers rather
    than rewriting old summary rows
  - rollback preserves earlier compacted history when it still describes the
    retained prefix and only removes support state that depends on rolled-back
    local turns
  - fork-point protection was applied to both visibility overlays and in-place
    tail rewrites so anchored history cannot drift after branching
- verification evidence:
  - `cd core_matrix && bin/rails test test/models/conversation_import_test.rb test/models/conversation_summary_segment_test.rb test/services/conversations/add_import_test.rb test/services/conversation_summaries/create_segment_test.rb test/services/conversations/rollback_to_turn_test.rb test/integration/transcript_import_summary_flow_test.rb`
    passed with `11 runs, 41 assertions, 0 failures, 0 errors`
- checklist notes:
  - no separate manual checklist delta was retained for this task because the
    landed behavior is transcript-support infrastructure covered by automated
    tests
- retained findings:
  - branch-prefix imports need to validate against both the branch parent and
    the resolved anchor message; generic conversation references are not enough
  - summary segments must be validated against transcript projection order
    rather than raw message ids so branch-prefix history can participate without
    transcript copying
  - rollback cleanup must restore older summary segments from a superseded state
    when the newer superseding segment falls behind the rollback boundary
  - fork-point safety is cross-cutting; visibility overlays and rewrite
    services both needed the same protection rule
- carry-forward notes:
  - Task 09 should consume these import and summary rows as transcript-support
    inputs instead of rebuilding separate compaction metadata
  - later publication and UI work should treat branch-prefix imports and active
    summary segments as explicit support records, not as implied transcript text
