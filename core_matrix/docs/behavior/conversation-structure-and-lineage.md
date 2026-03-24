# Conversation Structure And Lineage

## Purpose

Task 07.1 adds the base conversation aggregate for Core Matrix. Conversation
rows now carry workspace ownership, lineage shape, lifecycle state, and purpose
without introducing turn, message, transcript, or selector persistence yet.

## Conversation Behavior

- A `Conversation` belongs to a workspace and installation.
- Conversation identity does not point directly at an agent installation. The
  logical agent path remains `conversation -> workspace -> user_agent_binding ->
  agent_installation`.
- Conversation kind is orthogonal to purpose and lifecycle state.
- Supported v1 conversation kinds are:
  - `root`
  - `branch`
  - `thread`
  - `checkpoint`
- Supported v1 lifecycle states are:
  - `active`
  - `archived`
- Supported v1 purposes are:
  - `interactive`
  - `automation`

## Kind Rules

- `root` conversations have no parent conversation and no historical anchor.
- `branch` conversations require both a parent conversation and a
  `historical_anchor_message_id`.
- `thread` conversations require a parent conversation and may optionally carry
  a `historical_anchor_message_id` for provenance.
- `checkpoint` conversations require both a parent conversation and a
  `historical_anchor_message_id`.
- child conversations must stay in the same workspace as their parent
- Branch, thread, and checkpoint creation preserve lineage only; they do not
  imply transcript cloning.

## Purpose And Lifecycle Rules

- `interactive` remains the default user-facing conversation purpose.
- `automation` is root-only in v1.
- Branch, thread, and checkpoint creation against automation-purpose parents is
  rejected.
- Archive and unarchive only change lifecycle state; they do not rewrite
  lineage.

## Closure Behavior

- `ConversationClosure` stores ancestor and descendant pairs plus `depth`.
- Every created conversation gets a self-closure row with `depth = 0`.
- Child conversations inherit the full ancestor chain from the parent and add a
  new self row.
- Closure uniqueness is enforced per installation, ancestor, and descendant.

## Service Behavior

- `Conversations::CreateRoot` creates an active interactive root conversation.
- `Conversations::CreateAutomationRoot` creates an active automation root
  conversation.
- `Conversations::CreateBranch`, `CreateThread`, and `CreateCheckpoint` create
  child conversations under an existing parent and materialize closure-table
  lineage in the same transaction.
- `Conversations::Archive` moves a conversation to `archived`.
- `Conversations::Unarchive` moves a conversation back to `active`.

## Invariants

- conversation ownership stays rooted in workspace, not a direct agent foreign
  key
- conversation kind, purpose, and lifecycle remain distinct state axes
- automation conversations stay root-only and read-only in v1
- closure-table lineage is preserved without transcript copying

## Failure Modes

- unsupported conversation kinds, purposes, or lifecycle states are rejected
- non-root conversations without a parent are rejected
- branch and checkpoint conversations without a historical anchor are rejected
- automation conversations with non-root kinds are rejected
- duplicate closure rows are rejected
- negative closure depths are rejected
- child conversations that point at a different workspace from their parent are
  rejected

## Reference Sanity Check

The retained conclusion from the OpenClaw and Dify reference sweep is narrow:
neither reference was treated as the authority for conversation lineage,
automation-purpose semantics, or closure storage in this task.

Core Matrix followed the local design doc as the source of truth and kept the
reference sweep only as a sanity check that we were not missing an obviously
better pre-existing shape.
