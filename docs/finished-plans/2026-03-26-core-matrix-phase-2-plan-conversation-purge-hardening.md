# Conversation Purge Hardening Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Harden conversation purge so deleted conversations remove phase-two agent-control residue, clean up attachment-backed runtime rows safely, and only delete the conversation shell after an explicit no-residue check.

**Architecture:** Keep purge as an explicit lifecycle service, but move its row-ownership and deletion order into a dedicated purge-plan object. Use bulk deletes for pure runtime rows, teardown-aware destroys for attachment-backed rows, and a final fail-closed verification before removing the conversation shell.

**Tech Stack:** Ruby on Rails, Active Record, Active Storage, Minitest, ripgrep, git

---

## Execution Order and Dependencies

Run the tasks in order.

1. Task 1 locks the missing behavior with failing regression tests.
2. Task 2 adds attachment and fail-closed tests so the service refactor cannot
   regress teardown behavior.
3. Task 3 introduces the purge graph and rewires `PurgeDeleted`.
4. Task 4 updates behavior docs and runs the final verification sweep.

Do not reorder them. The service refactor should happen only after the missing
contracts are encoded in tests.

## Completion Gate

Do not consider this work complete until:

- focused purge tests cover phase-two mailbox residue, attachment teardown, and
  fail-closed shell behavior
- `Conversations::PurgeDeleted` uses a centralized purge graph
- mailbox ownership resolution includes close-request items that do not have an
  `agent_task_run_id`
- attachment-backed rows are cleaned through teardown-aware paths
- behavior docs describe the hardened purge contract
- the documented verification commands have been run successfully

---

### Task 1: Lock the Agent-Control Regression

**Files:**
- Modify: `test/services/conversations/purge_deleted_test.rb`
- Modify: `test/test_helper.rb`

**Step 1: Write the failing test**

Add a regression that creates a deleted conversation with:

- an `AgentTaskRun`
- an execution-assignment mailbox item for that task
- a `ProcessRun` and `SubagentConnection`
- resource-close mailbox items for those resources
- report receipts that point to the mailbox items

Use payloads like:

```ruby
payload: {
  "resource_type" => "ProcessRun",
  "resource_id" => process_run.public_id,
  "close_request_id" => close_item.public_id
}
```

Assert that purge removes:

```ruby
assert_difference("AgentTaskRun.count", -1) do
  assert_difference("AgentControlMailboxItem.count", -3) do
    assert_difference("AgentControlReportReceipt.count", -2) do
      Conversations::PurgeDeleted.call(conversation: branch.reload)
    end
  end
end
```

**Step 2: Run the test to verify it fails**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test test/services/conversations/purge_deleted_test.rb
```

Expected: FAIL because purge leaves agent-control rows behind or raises on
foreign-key dependencies.

**Step 3: Add any missing test helper support**

If the test setup is too noisy, extend `test/test_helper.rb` with a small helper
for resource-close mailbox items. Keep it minimal and public-id based.

**Step 4: Re-run the same test file**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test test/services/conversations/purge_deleted_test.rb
```

Expected: still FAIL, but now the regression setup is stable and easy to read.

**Step 5: Commit the failing regression**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
git add test/services/conversations/purge_deleted_test.rb test/test_helper.rb
git commit -m "test: lock conversation purge agent-control regression"
```

### Task 2: Lock Attachment and Fail-Closed Behavior

**Files:**
- Modify: `test/services/conversations/purge_deleted_test.rb`
- Modify: `test/test_helper.rb`

**Step 1: Write the attachment teardown regression**

Add a deleted-conversation scenario with:

- a `MessageAttachment` created through `create_message_attachment!`
- a `WorkflowArtifact` created with `storage_mode: "attached_file"`
- attached files on both records

Assert both the model rows and `ActiveStorage::Attachment` rows disappear:

```ruby
assert_difference("MessageAttachment.count", -1) do
  assert_difference("WorkflowArtifact.count", -1) do
    assert_difference("ActiveStorage::Attachment.count", -2) do
      Conversations::PurgeDeleted.call(conversation: conversation.reload)
    end
  end
end
```

**Step 2: Write the fail-closed regression**

Add a test that proves the shell is not deleted if owned rows remain after the
purge stages.

If needed, stub a plan verification seam such as:

```ruby
fake_plan = Struct.new(:conversation) do
  def execute! = true
  def remaining_owned_rows? = true
end.new(conversation)

Conversations::PurgePlan.stub(:new, fake_plan) do
  assert_no_difference("Conversation.count") do
    Conversations::PurgeDeleted.call(conversation: conversation.reload)
  end
end
```

Assert the conversation still exists and remains `deleted`.

**Step 3: Run the purge test file to verify both tests fail**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test test/services/conversations/purge_deleted_test.rb
```

Expected: FAIL because the current purge code uses raw deletes for
attachment-backed rows and has no explicit fail-closed verification seam.

**Step 4: Tighten helper usage if needed**

Keep helper changes minimal. Prefer local setup in the test file unless it would
obscure the actual scenario.

**Step 5: Commit the second regression batch**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
git add test/services/conversations/purge_deleted_test.rb test/test_helper.rb
git commit -m "test: lock purge attachment and shell verification behavior"
```

### Task 3: Introduce the Purge Graph and Refactor the Service

**Files:**
- Create: `app/services/conversations/purge_plan.rb`
- Modify: `app/services/conversations/purge_deleted.rb`
- Modify: `test/services/conversations/purge_deleted_test.rb`

**Step 1: Write the purge-plan object**

Create a dedicated service object that collects ids and owner scopes under the
conversation lock.

Start from a shape like:

```ruby
module Conversations
  class PurgePlan
    def initialize(conversation:)
      @conversation = conversation
    end

    def execute!
      purge_publications!
      purge_mailbox_residue!
      purge_runtime_leases!
      purge_runtime_rows!
      purge_attachment_backed_rows!
      purge_conversation_metadata!
      purge_transcript_rows!
      purge_structural_rows!
    end

    def remaining_owned_rows?
      remaining_owned_scopes.values.any?(&:exists?)
    end
  end
end
```

**Step 2: Implement owner resolution for mailbox residue**

Resolve mailbox items from both:

- `agent_task_run_id` for execution assignments and task-owned close requests
- `payload["resource_type"]` + `payload["resource_id"]` for close requests on
  `ProcessRun` and `SubagentConnection`

Use public ids when matching payload-backed resource ownership.

**Step 3: Implement mixed deletion semantics**

Inside the plan:

- keep pure runtime rows on `delete_all`
- destroy `WorkflowArtifact` and `MessageAttachment`
- null `origin_attachment_id` inside the in-scope attachment set before
  destroying message attachments
- null turn selected-message pointers before deleting messages
- verify both the attachment-backed rows and their
  `ActiveStorage::Attachment` join rows are gone before removing the shell

Representative code:

```ruby
MessageAttachment.where(id: message_attachment_ids, origin_attachment_id: message_attachment_ids)
  .update_all(origin_attachment_id: nil, updated_at: Time.current)

MessageAttachment.where(id: message_attachment_ids).find_each(&:destroy!)
WorkflowArtifact.where(id: workflow_artifact_ids).find_each(&:destroy!)
```

**Step 4: Rewire `PurgeDeleted`**

Make `PurgeDeleted` responsible for orchestration only:

- lifecycle checks
- force-quiesce behavior
- blocker checks
- `plan.execute!`
- fail-closed verification
- final shell `delete`

The end of the service should look conceptually like:

```ruby
plan = Conversations::PurgePlan.new(conversation: @conversation)
plan.execute!
raise_invalid!(@conversation, :base, "must not purge while owned rows remain") if plan.remaining_owned_rows?

@conversation.delete
purged = true
```

Raise a validation error, not a silent no-op, if the plan reports unexpected
residue and the intended contract is to fail closed.

**Step 5: Run the focused purge tests**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test test/services/conversations/purge_deleted_test.rb
```

Expected: PASS.

**Step 6: Commit the service refactor**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
git add app/services/conversations/purge_plan.rb app/services/conversations/purge_deleted.rb test/services/conversations/purge_deleted_test.rb
git commit -m "refactor: harden conversation purge ownership graph"
```

### Task 4: Update Behavior Docs and Run Final Verification

**Files:**
- Modify: `docs/behavior/conversation-structure-and-lineage.md`
- Modify: `docs/behavior/workflow-scheduler-and-wait-states.md`
- Modify: `docs/plans/2026-03-26-core-matrix-phase-2-conversation-purge-hardening-design.md`

**Step 1: Update the lifecycle behavior doc**

In `docs/behavior/conversation-structure-and-lineage.md`, document that:

- physical purge uses an explicit ownership graph
- mailbox residue and attachment-backed rows are part of purge cleanup
- shell removal is fail-closed if owned rows remain

**Step 2: Update the workflow/close behavior doc**

In `docs/behavior/workflow-scheduler-and-wait-states.md`, document that:

- delete close contract still quiesces running work
- purge then removes mailbox residue, leases, and attachment-backed runtime
  rows
- `force: true` does not bypass final deletion or provenance guards

**Step 3: Re-read the design doc against shipped code**

Update the design doc if the implementation refined any edge-case wording,
especially around mailbox ownership resolution or attachment ancestry.

**Step 4: Run focused verification**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test test/services/conversations/purge_deleted_test.rb
```

Expected: PASS.

**Step 5: Run broader regression coverage**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test test/services/conversations/request_deletion_test.rb test/services/conversations/archive_test.rb test/requests/agent_api/resource_close_test.rb
```

Expected: PASS.

**Step 6: Commit docs and final verification state**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
git add docs/behavior/conversation-structure-and-lineage.md docs/behavior/workflow-scheduler-and-wait-states.md docs/plans/2026-03-26-core-matrix-phase-2-conversation-purge-hardening-design.md
git commit -m "docs: record hardened conversation purge behavior"
```

## Documentation Integrity Check

The plan was checked for completeness on `2026-03-26`.

- the goal is explicit and matches the approved design
- the task order is dependency-safe and automation-friendly
- each task names exact files
- each task includes concrete test or verification commands
- behavior-doc updates are explicit rather than implied
- the completion gate is strong enough to prevent claiming success on partial
  cleanup
