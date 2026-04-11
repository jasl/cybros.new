# Fenix App Runtime and Supervision UI Contract

## Goal

Define one durable app-facing contract for `Fenix` that supports:

- cowork-facing progress visibility
- verbose developer inspection
- supervision sidechat and status summaries
- acceptance and replayable evaluation artifacts

without coupling `Core Matrix` to agent business semantics.

## Why This Revision Exists

The current implementation proved that runtime facts, plan updates, workflow
state, and conversation context are all available. The weak point is not
missing data. The weak point is the semantic boundary.

Today, `Core Matrix` sometimes tries to infer user-facing business meaning from
runtime details such as:

- `provider round 6`
- `command_run_wait`
- `npm test`
- `npm install -g`
- `React app`
- `game files`

That approach does not scale. It overfits the `2048` acceptance benchmark and
violates the product boundary:

- `Agent` knows the task semantics
- `Core Matrix` knows the runtime, the conversation, and the durable state

This contract replaces runtime-first semantic guessing with plan-first
supervision.

## Responsibility Split

### Agent Responsibilities

The `Agent` runs inside `Core Matrix` and is optional at every semantic
boundary except one:

- it may emit `turn_todo_plan_update`

That is the only additional transparency interface this contract requires for
high-quality supervision.

`turn_todo_plan_update` is optional, not mandatory. If it is missing, the
system must still provide coarse supervision using runtime and lifecycle data.

The `Agent` must not be required to emit extra supervision-only fields
such as:

- `active_form`
- `progress_summary`
- `waiting_on`
- sidechat-specific text

Those remain derived concerns owned by `Core Matrix`.

### Core Matrix Responsibilities

`Core Matrix` owns:

- turn execution
- workflow and runtime evidence
- persisted turn todo plans and plan feed
- safe reusable main-thread context
- supervision snapshots
- prompt payload construction
- acceptance and replay evaluation dumps

This means `Core Matrix` must derive user-facing supervision from durable
inputs it already owns, not by asking the `Agent` for extra product
copy.

## Hard Rules

- Do not encode benchmark-specific or business-specific semantics in
  `Core Matrix`.
- Do not infer product meaning from framework names, package manager commands,
  or tool-specific strings.
- Do not require more than `turn_todo_plan_update` for agent-side transparency.
- Do not assume `turn_todo_plan_update` always exists.
- Do not let raw workflow labels, provider rounds, snake_case tool names, or
  wait tokens become default human-visible text.
- Do not use acceptance markdown artifacts as the product API.
- Do not preserve compatibility shims for the heuristic supervision path.
- Use `public_id` at every app-facing boundary.

## Canonical Read Models

The app exposes four durable read models:

### 1. Transcript View

Purpose:

- user-visible messages
- approvals and clarifications
- final assistant delivery

Transcript is not runtime truth and not supervision truth.

### 2. Turn Event Stream

Purpose:

- linear story of what happened inside a turn
- cowork and verbose rendering
- replayable evaluation inputs

This is chronology, not meaning.

### 3. Supervision View

Purpose:

- what is happening now
- what changed most recently
- what is being waited on
- what the active plan currently is
- what active subagents are doing

This is the semantic current-state model.

### 4. Debug View

Purpose:

- exact command lines
- raw workflow node refs
- exact tool and process metadata
- diagnostic joins for developer inspection

Debug data remains separate from cowork-facing surfaces.

## Plan-First Supervision

### Primary Principle

Human-visible supervision is anchored to the active plan item, not to the
currently executing runtime operation.

When a plan exists, the default semantic ladder is:

1. active `TurnTodoPlanItem`
2. recent plan transition feed
3. safe reusable main-thread context
4. generic runtime evidence
5. coarse lifecycle fallback

When no plan exists, the fallback ladder is:

1. generic runtime evidence
2. conversation request summary
3. safe reusable main-thread context
4. coarse lifecycle fallback

### Why This Works

This follows the strongest lessons from successful predecessors:

- Codex treats plan updates as first-class turn events
- Claude treats the current todo item as the best current-work anchor
- both systems keep runtime evidence available without making it the primary
  semantic source

### Plan Quality Requirements

For plan-first supervision to work well, `turn_todo_plan_update` must obey
these constraints:

- `goal_summary` is always present
- at most one item is `in_progress`
- `title` is written as a human task, not as a tool token or workflow label
- status transitions are accurate

This is a quality requirement on the single plan interface, not a request for
additional agent-side interfaces.

## Turn Event Stream

### Purpose

`TurnEventStream` is the canonical ordered runtime story for a turn. It is used
for:

- runtime transcript rendering
- live progress feed rendering
- replay dumps
- verbose inspection

### Source Inputs

The stream may derive from:

- workflow node lifecycle
- tool invocations
- command runs
- process runs
- plan feed entries
- subagent connection updates
- validation milestones
- artifact publication milestones

### Constraints

- event families must be generic
- event wording must be safe and tool-neutral by default
- debug refs may be attached, but not required for cowork rendering
- this stream must not invent business semantics

Good examples:

- `Started a shell command in /workspace/foo`
- `A process is still running in /workspace/foo`
- `Plan item completed: Add replay dump export`

Bad examples:

- `Started the React app`
- `Edited game files`
- `Running npm test`
- `Advancing provider round 6`

## Safe Reusable Main-Thread Context

### Purpose

Supervision needs compact, reusable context that survives across snapshots and
can be safely passed to a responder prompt.

This context is owned by `Core Matrix` and extracted from the main
conversation. It is not requested from the `Agent`.

### Principle Absorbed From Claude `/btw`

Claude's `/btw` succeeds because it answers from a safe slice of the main
thread context rather than from raw runtime internals. We should absorb that
principle, not copy the product surface literally.

In `Core Matrix`, the equivalent should be:

- derive from `Conversations::ContextProjection`
- use a bounded recent window
- remove raw in-progress runtime noise
- keep only safe reusable snippets

### Shape

The context model should prefer snippets over synthesized business claims.

Recommended fields:

```json
{
  "message_ids": ["msg_123"],
  "turn_ids": ["turn_123"],
  "snippets": [
    {
      "message_id": "msg_123",
      "turn_id": "turn_123",
      "role": "user",
      "slot": "input",
      "excerpt": "Please rebuild supervision around the active plan item.",
      "keywords": ["rebuild", "supervision", "active", "plan", "item"]
    }
  ]
}
```

### Constraints

- do not hardcode benchmark-specific summaries such as `2048 acceptance flow`
- do not hardcode generic template summaries such as `Context already references ...`
- do not promote one snippet into a business claim inside the context builder
- let the responder prompt decide how to use the snippets

## Runtime Evidence

### Purpose

Runtime evidence is the structured proof layer used when supervision needs to
justify waiting, blocking, or recent activity.

It exists to answer:

- is something currently running
- what kind of runtime object is active
- where is it happening
- did something recently fail or finish

It does not exist to answer what the task means.

### Recommended Shape

```json
{
  "active_command": {
    "command_run_public_id": "cmd_123",
    "cwd": "/workspace/foo",
    "command_preview": "npm test && npm run build",
    "lifecycle_state": "running",
    "started_at": "2026-04-07T10:00:00Z"
  },
  "active_process": null,
  "recent_failure": null,
  "workflow_wait_state": "waiting"
}
```

### Constraints

- no framework-specific business labels
- no package-manager-specific product meaning
- no benchmark-specific nouns
- safe command preview may exist, but exact command line belongs to `DebugView`

## Supervision View

### Required Fields

`SupervisionView` should expose:

- `overall_state`
- `request_summary`
- `primary_turn_todo_plan_view`
- `active_subagent_turn_todo_plan_views`
- `recent_plan_transitions`
- `context_snippets`
- `runtime_evidence`
- `blocked_summary`
- `next_step_hint`

### Derived Human-Visible Fields

The current persisted fields may remain for now:

- `current_focus_summary`
- `recent_progress_summary`
- `waiting_summary`
- `next_step_hint`

But they should become derived outputs from the canonical inputs above, not
their own separate truth source.

### Fallback Contract

When a persisted plan exists:

- `current_focus_summary` derives from the current plan item
- `recent_progress_summary` derives from recent plan transitions
- `waiting_summary` derives from runtime evidence only when the current state is
  actually waiting or blocked

When no persisted plan exists:

- `current_focus_summary` may fall back to coarse runtime status
- wording must stay generic
- no business or toolchain inference is allowed

## Supervision Responder Prompt Contract

### Principle

The responder is a derived query over the frozen canonical payload, similar in
spirit to Claude `/btw`.

It should:

- answer from a safe bounded payload
- prefer plan semantics over runtime wording
- use runtime evidence only to justify waiting, blocking, or completion
- be a single-response derived query with no tool access
- never expose raw runtime tokens by default

### System Prompt Shape

Recommended prompt intent:

- answer in the user's language
- base the answer only on the provided payload
- answer in one response with no tools and no promises of future actions
- prefer the active plan item for current work
- prefer recent plan transitions for recent progress
- use context snippets for subject nouns only when the plan is too generic
- use runtime evidence only for waiting, blocked, or coarse fallback states
- do not mention snapshots, provenance, provider names, workflow labels, tool
  names, or internal ids
- keep the answer short

### User Payload Shape

Recommended structure:

```json
{
  "question": "What are you doing now and what changed recently?",
  "supervision": {
    "overall_state": "running",
    "request_summary": "Refactor supervision to be plan-first.",
    "primary_turn_todo_plan": {
      "goal_summary": "Rebuild runtime and supervision around plan-first semantics.",
      "current_item_title": "Rewrite the supervision prompt payload",
      "current_item_status": "in_progress"
    },
    "recent_plan_transitions": [
      { "summary": "Replace heuristic context summarization completed." }
    ],
    "context_snippets": [
      { "excerpt": "Sidechat should use the active plan item as the semantic anchor." }
    ],
    "runtime_evidence": {
      "active_command": {
        "cwd": "/workspace/core_matrix",
        "command_preview": "bin/rails test ..."
      }
    }
  }
}
```

## Acceptance and Replay Evaluation

### New Requirement

Acceptance should dump a replayable supervision evaluation bundle so iteration
does not require a full `2048` rerun every time.

### Required Artifact

Each fresh acceptance run should export a canonical replay bundle such as:

- `review/supervision-eval-bundle.json`

Suggested contents:

- frozen `machine_status`
- canonical plan view
- recent plan transitions
- context snippets
- runtime evidence
- sidechat questions
- expected contract flags

### Replay Workflow

Local development should support:

1. run one fresh acceptance
2. replay supervision rendering from the exported dump
3. iterate on payload shaping and prompt behavior locally
4. rerun full acceptance only for final confirmation

This lowers cost and speeds supervision tuning without weakening the final gate.

## Reference Principles Absorbed

### From Codex

- explicit plan updates are first-class turn events
- plan state is durable and app-facing
- UI may track checklist progress directly without extra semantic interfaces

### From Claude

- current todo is the strongest current-work anchor
- side questions should answer from safe reusable main-thread context
- derived responses should not directly replay raw execution tokens

### What We Intentionally Do Not Copy

- we do not require agent-side `active_form`
- we do not require sidechat-specific agent callbacks
- we do not put business semantics into runtime classifiers

## Migration Notes

- breaking cleanup is allowed
- delete heuristic supervision wording paths
- do not backfill old data
- do not preserve old payload compatibility
- rebuild acceptance expectations around the new canonical payloads
