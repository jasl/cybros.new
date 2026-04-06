# Turn Todo Plan And Supervision Design

## Goal

Replace the current supervision-side reconstruction of progress with a first-class, turn-scoped todo plan that the agent maintains explicitly while it works.

The new `TurnTodoPlan` becomes the source of truth for UI checklist display,
supervision feed generation, and supervision conversation answers. The older
approach of inferring plan/progress from runtime summaries or humanized
workflow details is removed.

## Problem

The current product effect is not good enough at exposing the current state of
conversation work.

The existing design has two structural problems:

1. human-visible progress is derived from supervision summaries instead of from
   an explicit execution plan
2. feed and sidechat are forced to translate internal runtime state into
   something that resembles a user-facing work report

That leaves the system with no stable source for:

- "what tasks does the agent think it is doing right now?"
- "which task is in progress?"
- "which child agent is working on which delegated task?"
- "how should checklist UI, feed, and sidechat stay consistent with each other?"

The result is a supervision surface that can sound plausible but is not backed
by a first-class plan object.

## Product Target

The target product behavior is closer to the Codex task checklist UI:

- a turn-scoped ordered checklist
- explicit task statuses
- a stable completed/total progress count
- child-agent work visible as delegated or subordinate plan work
- the same data source powering:
  - sidebar checklist UI
  - dashboard and kanban summaries
  - detailed turn feed
  - supervision conversation answers

This is a UI and UX feature, not a new audit log. Workflow and runtime events
remain the stronger audit substrate.

## Non-Goals

This redesign does not introduce a second structured execution-state domain
next to `TurnTodoPlan`.

Specifically:

- do not add an OpenClaw-style execution-item model for tool, command, patch,
  or approval progress
- do not create a separate persisted "thinking transcript" domain
- do not treat Codex-style inline conversation affordances such as "Worked for
  39s" or "Explored 4 files, 1 search" as a new source-of-truth model

If the product later wants conversation-inline work traces like the Codex UI,
those should be rendered from existing workflow/runtime projections such as:

- active workflow nodes
- workflow node events
- conversation runtime events

That rendering layer must not become a second persisted execution-state
domain.

## Destructive Assumptions

- This redesign is intentionally destructive.
- No compatibility aliases should be preserved for old plan pathways.
- `TurnTodoPlan` replaces `AgentTaskPlanItem` as the primary plan model.
- `execution_progress.progress_payload.supervision_update.plan_items` is
  removed.
- `ConversationSupervision` no longer owns plan truth.
- Existing feed types that only existed to approximate progress without an
  explicit plan should be removed.

## Reference Findings

### Codex

Codex is the strongest reference for the intended behavior.

It treats the agent todo list as a first-class turn item rather than as a
sentence hidden in the final answer. The relevant traits are:

- turn-scoped checklist lifecycle
- explicit ordered items
- compact item status model
- stable UI-readable object for progress rendering

This is the closest match to the desired product outcome.

### Claude Code

Claude Code separates two ideas that should not be conflated:

- a long-form plan document for design or execution setup
- a lightweight todo list for execution tracking

That split is useful here. The new `TurnTodoPlan` should correspond to the
execution-tracking todo list, not to a long-form implementation plan document.

### OpenCode

OpenCode's strongest relevant idea is that planning is an explicit capability,
not something inferred from execution logs after the fact.

That reinforces the main design choice: the agent should maintain the plan
itself, and supervision should consume that explicit plan instead of asking the
runtime to guess it.

## Design Principles

### 1. Plan truth is explicit and agent-maintained

The current turn plan is whatever the agent most recently published as its
`TurnTodoPlan`.

The server may validate and project that plan, but it does not invent it.

### 2. Supervision is a read model

`ConversationSupervision` is not the source of plan truth. It consumes:

- runtime state
- active `TurnTodoPlan` objects
- turn-scoped feed entries

and produces:

- compact conversation supervision state
- frozen snapshots
- natural-language supervision answers

### 3. Feed is append-only and turn-scoped

The current plan is mutable. The feed is not.

When the agent replaces the current `TurnTodoPlan` contents, the system diffs
the old and new plan heads and appends feed entries. Existing feed entries are
never rewritten or deleted because of a later plan update.

### 4. Workflow owns audit, plan owns UX

Workflow/runtime rows remain the stronger operational evidence.

`TurnTodoPlan` exists to power product-facing observability:

- checklist UI
- feed
- sidechat answers
- dashboard summaries

It does not need the full audit semantics of workflow history.

If the product later wants inline "worked for" or "explored files" UI inside
the conversation transcript, that should be treated as a renderer over
workflow/runtime state rather than as a new persisted execution object.

### 5. Child work has its own plan

Subagents should not be flattened into parent checklist text.

Each child agent maintains its own turn-scoped plan through its own active
`AgentTaskRun`. Parent plans may point at delegated child sessions, and
supervision aggregates those active child plans.

### 6. No dual sources

There must be exactly one source of truth for execution checklist state:

- `TurnTodoPlan`

Old models and old summary-driven plan approximations must be removed from the
main path.

## Domain Model

## `TurnTodoPlan`

`TurnTodoPlan` is the mutable current plan head for one executing agent task.

Recommended fields:

- `installation_id`
- `agent_task_run_id`
- `conversation_id`
- `turn_id`
- `status`
- `goal_summary`
- `current_item_key`
- `updated_at`
- `closed_at`

Ownership rules:

- `TurnTodoPlan` belongs directly to `AgentTaskRun`
- each active `AgentTaskRun` may have at most one active `TurnTodoPlan`
- child-agent plans are also owned by their own `AgentTaskRun`, not by
  `SubagentSession`

Implementation note:

- prefer an explicit `agent_task_run_id` foreign key over a polymorphic owner
  column
- add database-level cascading cleanup from `agent_task_runs` to
  `turn_todo_plans` to avoid orphaned rows during conversation purge and other
  runtime cleanup flows

Plan statuses:

- `draft`
- `active`
- `blocked`
- `completed`
- `canceled`
- `failed`

## `TurnTodoPlanItem`

`TurnTodoPlanItem` stores the current checklist items for a plan.

Recommended fields:

- `turn_todo_plan_id`
- `item_key`
- `title`
- `status`
- `position`
- `kind`
- `details_payload`
- `delegated_subagent_session_id`
- `depends_on_item_keys`
- `last_status_changed_at`

Item statuses:

- `pending`
- `in_progress`
- `completed`
- `blocked`
- `canceled`
- `failed`

Unlike the legacy `AgentTaskPlanItem`, multiple items may be `in_progress` at
the same time. `current_item_key` identifies the plan's primary focus, not the
only active item.

## Update Protocol

Execution progress reports should introduce a new plan-specific payload:

```json
{
  "turn_todo_plan_update": {
    "goal_summary": "Rebuild conversation supervision around turn todo plans",
    "current_item_key": "aggregate-subagent-plans",
    "items": [
      {
        "item_key": "define-domain",
        "title": "Replace AgentTaskPlanItem with TurnTodoPlan",
        "status": "completed",
        "position": 0,
        "kind": "implementation"
      },
      {
        "item_key": "aggregate-subagent-plans",
        "title": "Project child plans into conversation supervision",
        "status": "in_progress",
        "position": 1,
        "kind": "implementation",
        "depends_on_item_keys": ["define-domain"]
      }
    ]
  }
}
```

Rules:

- each update is a full replacement of the current plan head
- the server validates and applies the new plan
- the server diffs old and new plan heads to generate append-only feed entries
- the server does not require plan revision storage for this feature

`TurnTodoPlans::ApplyUpdate` should:

1. load the current head plan for the target `AgentTaskRun`, if any
2. validate the incoming plan snapshot
3. replace the mutable plan head
4. replace current plan items
5. append canonical feed entries from the old/new diff
6. trigger conversation supervision projection refresh

## Conversation Supervision Architecture

`ConversationSupervision` consumes `TurnTodoPlan`, not the other way around.

### Current supervision projection

`ConversationSupervisionState` remains the compact conversation-scoped read
model. It should keep fields such as:

- `overall_state`
- `current_owner_kind`
- `current_owner_public_id`
- `request_summary`
- `current_focus_summary`
- `recent_progress_summary`
- `waiting_summary`
- `blocked_summary`
- `next_step_hint`
- `board_lane`

It should not store full checklist items as the source of truth.

### Snapshot payload

Supervision snapshots should freeze a plan-centric bundle payload:

- `primary_turn_todo_plan_view`
- `active_subagent_turn_todo_plan_views`
- `turn_feed`
- `conversation_context_view`
- `capability_authority`

Snapshots freeze the plan view payload directly. They do not need a
`plan_revision_id`.

### Sidechat behavior

Natural-language supervision answers should be generated from frozen plan view
payloads.

Examples:

- "What are you doing right now?" -> current primary item title
- "What remains?" -> pending and blocked items from the frozen plan
- "What is the subagent doing?" -> active child plan current item
- "What changed most recently?" -> latest meaningful turn feed entry

The older strategy of guessing plan state from summary text should be removed.

## API And UI Contract

## `TurnTodoPlanView`

This is the stable UI and API resource for checklist rendering.

```json
{
  "turn_todo_plan_id": "plan_...",
  "conversation_id": "conv_...",
  "turn_id": "turn_...",
  "owner": {
    "kind": "agent_task_run",
    "id": "task_...",
    "subagent_session_id": null
  },
  "status": "active",
  "goal_summary": "Rebuild conversation supervision around turn todo plans",
  "current_item_key": "aggregate-subagent-plans",
  "progress": {
    "total": 7,
    "completed": 2,
    "in_progress": 2,
    "pending": 3,
    "blocked": 0,
    "failed": 0,
    "canceled": 0,
    "completion_ratio": 0.2857
  },
  "items": [
    {
      "item_key": "define-domain",
      "title": "Replace AgentTaskPlanItem with TurnTodoPlan",
      "status": "completed",
      "position": 0,
      "kind": "implementation",
      "delegated_subagent_session_id": null,
      "depends_on_item_keys": []
    }
  ],
  "updated_at": "..."
}
```

Uses:

- sidebar checklist
- expanded detail panel
- supervision conversation snapshot

## `ConversationSupervisionView`

This is the compact dashboard and board projection.

```json
{
  "conversation_id": "conv_...",
  "overall_state": "running",
  "board_lane": "active",
  "request_summary": "...",
  "current_focus_summary": "...",
  "recent_progress_summary": "...",
  "waiting_summary": null,
  "blocked_summary": null,
  "next_step_hint": "...",
  "primary_turn_todo_plan": { "...compact TurnTodoPlanView..." },
  "active_subagent_turn_todo_plans": [
    { "...compact TurnTodoPlanView..." }
  ],
  "turn_feed_preview": [
    { "...FeedEntry..." }
  ],
  "updated_at": "..."
}
```

Uses:

- kanban board cards
- dashboard summaries
- compact sidebar cards

## Feed Model

Feed remains a turn-scoped append-only UX timeline.

The system should keep lifecycle and control events that remain meaningful, and
introduce plan-centric events that directly reflect `TurnTodoPlan` changes.

Recommended canonical feed kinds:

- `turn_started`
- `turn_completed`
- `turn_failed`
- `turn_interrupted`
- `waiting_started`
- `waiting_cleared`
- `blocker_started`
- `blocker_cleared`
- `control_requested`
- `control_completed`
- `control_failed`
- `turn_todo_plan_created`
- `turn_todo_goal_changed`
- `turn_todo_item_added`
- `turn_todo_item_removed`
- `turn_todo_item_reordered`
- `turn_todo_item_started`
- `turn_todo_item_completed`
- `turn_todo_item_blocked`
- `turn_todo_item_failed`
- `turn_todo_item_canceled`
- `turn_todo_item_reopened`
- `turn_todo_item_delegated`
- `turn_todo_plan_completed`

Old feed kinds that only existed because the system lacked a first-class plan
should be removed from the main path, especially:

- `progress_recorded`
- `subagent_started`
- `subagent_completed`

## State Derivation Rules

### Runtime state

`overall_state` and `board_lane` remain runtime-first:

- workflow and task lifecycle decide whether work is queued, active, waiting,
  blocked, done, or failed
- plan does not override runtime state

### Focus and summary text

Human-readable summaries should be plan-first:

- `request_summary` -> `TurnTodoPlan.goal_summary`
- `current_focus_summary` -> primary current item title
- `recent_progress_summary` -> latest meaningful feed entry summary
- `next_step_hint` -> next runnable pending item, or child-result continuation

Waiting and blocked summaries remain runtime-derived, but may incorporate the
associated current plan item title for context.

## Cleanup Contract

The redesign is only complete when the old plan architecture is removed from
the main path.

Required cleanup:

- remove `AgentTaskPlanItem` as the primary plan model
- remove `AgentTaskRuns::ReplacePlanItems`
- reject `supervision_update.plan_items`
- do not add any replacement execution-item domain alongside `TurnTodoPlan`
- remove supervision snapshot payloads centered on `active_plan_items`
- remove sidechat logic that reconstructs plan state from summary text
- remove old feed kinds that no longer match the new plan-driven UX model
- update purge/lifecycle cleanup paths so `TurnTodoPlan` rows are collected and
  deleted safely with their owner task runs
- update behavior docs that still present `AgentTaskPlanItem` as the active
  product contract

## End State

At the end of this redesign, Core Matrix should have:

- one explicit mutable `TurnTodoPlan` per active `AgentTaskRun`
- child agents maintaining their own turn-scoped plans
- conversation supervision consuming plan views instead of inventing them
- append-only turn feed entries derived from plan diffs and runtime boundaries
- stable plan-centric API and UI contracts
- supervision conversation answers grounded in frozen plan views
- deleted legacy plan pathways and deleted weak feed types that no longer fit
