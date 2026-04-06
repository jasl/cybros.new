# Fenix App Runtime and Supervision UI Contract

## Goal

Define one app-facing contract for `Fenix` that supports both product styles
without splitting the execution model:

- `Cowork mode` as the default product style
- `Verbose mode` as a developer-facing inspection style

The contract is built on two orthogonal read models:

- one canonical linear per-turn runtime event stream
- one canonical supervision read model for "what is happening now"

Everything else is a renderer over those two models plus the conversation
transcript and artifact metadata.

## Why This Revision Exists

The previous draft was directionally right but still too loose around
supervision.

The `2048` acceptance bundle now proves that runtime facts, command metadata,
plan state, and validation milestones already exist in durable form. The weak
point is not missing evidence. The weak point is that human-visible supervision
sometimes falls back to low-information labels such as:

- `provider round 6`
- `command_run_wait`
- raw tool names

That is a contract problem, not a renderer polish problem.

We need one design that explains:

- how a turn becomes a linear UI story
- how supervision stays semantic instead of replaying internal runtime labels
- how cowork and verbose renderers share the same substrate
- how to remove compatibility baggage instead of layering more adapters

## Product Decisions

- `Cowork mode` is the default app experience.
- `Verbose mode` is an alternate renderer, not a second backend model.
- Supervision remains a first-class surface and is not derived from ad hoc
  transcript parsing.
- Runtime detail should be inspectable without flooding the main transcript.
- This revision assumes breaking cleanup is allowed. Do not preserve old
  observation-era UI contracts for the new app-facing model.

## Hard Rules

- Do not invent a second execution-state domain just to support a different UI
  style.
- Do not let `workflow_node_key`, provider round labels, raw tool names, or
  wait-state tokens become default human-visible text.
- Do not build sidechat directly from raw transcript text or raw runtime event
  names.
- Do not make acceptance markdown files themselves the product API.
- Do not keep compatibility shims in the new app-facing contract just because
  old payloads existed.
- Use `public_id` at every app-facing boundary.

## Canonical Read Models

The app should expose five app-facing read models. Only two of them are new
core execution projections.

### 1. Transcript View

Purpose:

- user-facing conversation transcript
- assistant delivery messages
- approval / clarification asks
- concise work-summary insertions when product wants them

This is the main conversation surface, not the runtime truth.

### 2. Turn Event Stream

Purpose:

- linear "what happened inside this turn" projection
- lane-aware, phase-aware, renderable in both cowork and verbose modes

This is the canonical execution-story model for a single turn.

### 3. Supervision View

Purpose:

- current work
- recent meaningful change
- blocker / waiting state
- active subagents
- current turn todo plan
- recent feed
- sidechat-ready semantic grounding

This is the canonical "what is happening now" model.

### 4. Artifact and Validation View

Purpose:

- changed files
- exports / debug exports
- playable preview state
- host validation results
- artifact availability

### 5. Debug View

Purpose:

- low-level runtime evidence
- raw ids and payload refs
- exact workflow node keys
- exact commands and process metadata
- evidence joins for developer inspection

This remains separate from cowork-facing surfaces.

## Capability Consolidation

This revision is not only a wording cleanup. It is a consolidation plan for
existing app-facing execution visibility.

The target shape is:

- one canonical `TurnEventStream` for linear turn-internal runtime story
- one canonical `SupervisionView` for current-state semantics
- transcript and debug staying separate instead of leaking into those models

### Existing Surfaces That Should Collapse Into `TurnEventStream`

These surfaces are currently overlapping runtime projections and should become
renderers or APIs backed by the same event stream:

- acceptance runtime transcript generation
- acceptance live progress feed generation
- artifact runtime summaries that currently re-derive activity wording
- provider-backed fallback feed synthesis when no persisted turn todo plan exists

The key cleanup rule is:

- keep the underlying facts
- remove duplicate humanization layers
- stop letting each surface invent its own runtime wording

### Existing Surfaces That Should Collapse Into `SupervisionView`

These surfaces are currently different renderings of "what is happening now"
and should share one semantic source:

- machine-status payload fields such as `current_focus_summary`,
  `recent_progress_summary`, `waiting_summary`, and `next_step_hint`
- sidechat responses
- human summary responses
- board-card current-status summaries
- app-facing conversation turn feed listing
- provider-backed fallback current-work summaries
- subagent current-progress summaries used in supervision payloads

The key cleanup rule is:

- sidechat and status summaries should consume semantic supervision fields
- semantic supervision fields may use runtime hints
- human-visible supervision must not read directly from raw workflow or tool
  labels

### Surfaces That Must Stay Separate

The following are still first-class but should not be merged into the same
model:

- transcript messages stay transcript messages
- debug and verbose evidence keep exact refs, raw labels, and exact commands
- acceptance markdown files are validation artifacts, not the product API

This means the new contract should remove duplication at the projection layer
without collapsing user conversation, supervision, and developer debugging into
one payload.

## Core Architecture

The app should treat execution visibility as two linked but distinct layers.

### Layer A: Linear Turn Runtime Projection

This answers:

- what happened during this turn
- in what order
- on which lane
- with what user-safe summary

It is optimized for replayability and inspection.

### Layer B: Semantic Supervision Projection

This answers:

- what is happening right now
- what changed most recently
- what is being waited on
- what the active plan currently is

It is optimized for current-state visibility and natural-language answering.

### Relationship Between Them

- supervision may consume semantic hints from the turn event stream
- supervision must not become a thin wrapper over raw event labels
- runtime panels may show more detail than supervision
- verbose mode may expose exact commands and event refs
- cowork mode should prefer semantic summaries over execution labels

That separation is the maintainability boundary:

- `TurnEventStream` owns inside-the-turn chronology
- `SupervisionView` owns current-state meaning
- transcript owns user-visible conversation delivery
- debug owns exact runtime evidence and unsafe-or-noisy internals

## Canonical Turn Event Stream

### Purpose

`TurnEventStream` is the single app-facing projection for turn-internal work.

It should replace ad hoc mixtures of:

- transcript snippets
- raw workflow node humanization
- runtime panel-specific formatting
- sidechat-specific special cases

### Source Inputs

The stream may derive from:

- conversation messages
- `TurnTodoPlan` / `TurnTodoPlanItem` views
- canonical `turn_feed`
- workflow node lifecycle
- tool invocations
- command runs
- process runs
- subagent session updates
- supervision snapshots when they materially affect the story
- host validation milestones
- artifact publication milestones

### Required Event Shape

Every event should support these fields where applicable:

- `event_public_id`
- `sequence`
- `timestamp`
- `conversation_public_id`
- `turn_public_id`
- `actor_type`
- `actor_label`
- `actor_public_id`
- `phase`
- `family`
- `kind`
- `status`
- `summary`
- `detail`
- `source_refs`

Execution-linked refs may additionally include:

- `workflow_run_public_id`
- `workflow_node_public_id`
- `workflow_node_key`
- `workflow_node_ordinal`
- `tool_invocation_public_id`
- `command_run_public_id`
- `process_run_public_id`
- `subagent_session_public_id`

UI-oriented semantic hints may additionally include:

- `work_type`
- `goal_summary`
- `safe_focus_summary`
- `safe_progress_summary`
- `wait_reason_summary`
- `next_step_hint`
- `command_summary`
- `path_summary`
- `user_visible`

### Event Families

Minimum families:

1. `conversation_message`
2. `runtime_progress`
3. `tool_activity`
4. `command_activity`
5. `process_activity`
6. `subagent_progress`
7. `supervision_update`
8. `host_validation`
9. `artifact_update`

### Semantic Enrichment Rules

This is where the current system is still too weak.

The event stream must carry user-safe summaries in addition to exact runtime
refs.

#### Provider rounds

- provider round labels are classification hints only
- they must not be the primary cowork or sidechat wording
- an enriched event should prefer request-oriented wording such as:
  - `Implementing the 2048 app`
  - `Checking the test run`
  - `Preparing the final validation step`

#### Tool activity

- raw tool names may exist in debug refs
- cowork-visible summaries should describe the purpose of the work
- `command_run_wait` is not a user-facing activity description

#### Commands

Commands should produce both:

- exact command metadata for verbose/debug
- a safe command summary for cowork/supervision

Examples:

- exact: ``cd /workspace/game-2048 && npm test && npm run build``
- safe summary: `running the test-and-build check in /workspace/game-2048`

The safe summary should prefer classification over raw shell when possible:

- scaffold project
- edit files
- run tests
- run build
- start preview server
- inspect workspace
- wait for command to finish

When the exact command is short, low-risk, and explanatory, verbose mode may
show it directly. Cowork and supervision should default to the safe summary.

#### Processes

Process events should expose:

- purpose
- workspace path
- current lifecycle

Example:

- cowork/supervision: `preview server is starting in /workspace/game-2048`
- verbose/debug: exact `npm run preview`

## Canonical Supervision View

### Purpose

`SupervisionView` is the stable read model for current-state answering.

It should be reconstructible from durable runtime rows and existing
projections. It is not a second execution domain and it is not a transcript
parser.

### Source Inputs

`SupervisionView` should derive from:

- `ConversationSupervisionState`
- `primary_turn_todo_plan_view`
- `active_subagent_turn_todo_plan_views`
- canonical `turn_feed`
- active `CommandRun` / `ProcessRun` references when relevant
- recent semantic hints from `TurnEventStream`
- conversation facts / request summary

### Required Shape

Minimum fields:

- `overall_state`
- `current_work_summary`
- `recent_progress_summary`
- `waiting_summary`
- `blocked_summary`
- `next_step_hint`
- `primary_turn_todo_plan_view`
- `active_subagent_turn_todo_plan_views`
- `turn_feed`
- `runtime_focus_hint`
- `grounding`

`runtime_focus_hint` is important. It should capture the current concrete
execution subject when the plan alone is too abstract, for example:

- active command summary
- active process summary
- active host validation step

### Sidechat Contract

Sidechat should render from `SupervisionView`, not from raw event labels.

It should answer in this order:

1. current work
2. most recent meaningful change
3. waiting / blocker reason when relevant
4. next justified step when supported
5. compact grounding when helpful

### Sidechat Rules

#### Current work

Prefer, in order:

1. current turn todo item title if it is already user-meaningful
2. runtime focus hint if it is more concrete and still safe
3. request-oriented work summary

Bad outputs:

- `advancing provider round 6`
- `running command_run_wait`

Good outputs:

- `continuing the 2048 app implementation`
- `running the test-and-build check in /workspace/game-2048`
- `waiting for the preview server to finish starting`

#### Recent change

Prefer the latest meaningful semantic milestone, for example:

- tests finished
- build failed
- helper result arrived
- waiting started
- preview server became reachable

Do not say:

- `provider round 6 just started`
- `command_run_wait started`

unless the user explicitly asked for verbose/runtime details.

#### Waiting and blockers

When the current work is a command wait or process wait, the visible wording
should mention what is being waited on, not just the wait primitive.

Examples:

- `I am waiting for npm test to finish in /workspace/game-2048.`
- `I am waiting for the preview server in /workspace/game-2048 to become reachable.`

If the exact command is not safe or not concise enough, fall back to a safe
summary:

- `I am waiting for the current verification command to finish.`

#### Human-visible leak rule

Cowork-visible supervision text must not expose:

- `provider_round_*`
- raw snake_case tool names
- `command_run_wait`
- `process_exec`
- workflow node keys
- internal event kinds

Those belong in verbose/debug surfaces only.

## UI Surface Contract

### Main Transcript

Render:

- user messages
- assistant messages
- short work summaries
- approvals and clarification asks
- final delivery summaries

Do not default to rendering:

- provider-round churn
- every tool call
- every command/process event
- supervision implementation details

### Turn Runtime Panel

Render from `TurnEventStream`.

Show:

- linear turn timeline
- actor lanes
- grouped phases
- tool / command / process summaries
- subagent progress
- host validation milestones
- supervision checkpoints when they materially change the story

Cowork mode:

- concise summaries first
- grouped `Plan`, `Build`, `Validate`, `Deliver`
- expandable details

Verbose mode:

- more event rows
- exact command and process metadata
- raw runtime refs available inline or in an inspector

### Supervision Panel

Render from `SupervisionView`.

Show:

- current focus
- recent progress
- waiting / blocker state
- active subagents
- primary turn todo plan
- recent turn feed
- sidechat transcript

This panel should answer "what is happening now," not retell the whole turn.

### Side Panels

Render:

- changed files
- artifacts
- playable verification results
- subagent roster
- export / debug-export availability

### Debug Panel

Render from `DebugView` and exact runtime refs.

Show:

- raw ids and payload refs
- exact workflow node keys
- exact command lines
- exact process metadata
- evidence links

This is where developer-facing internals belong.

## Event Placement Rules

### Main Transcript Only

- user messages
- assistant-facing explanations
- approvals / questions
- final answer

### Runtime Panel Only

- provider progression
- tool summaries
- command / process activity
- subagent execution detail
- host validation checkpoints

### Supervision Panel Only

- current focus
- recent semantic progress
- wait / blocker state
- sidechat
- current turn feed

### Debug Only

- raw workflow node keys
- raw event kinds
- exact tool payload refs
- exact command lines when not cowork-safe

## Acceptance Gate

The `2048` capstone should prove that the app substrate supports both render
modes and semantic supervision.

Minimum required artifacts remain:

- `review/conversation-transcript.md`
- `review/turn-runtime-transcript.md`
- `review/supervision-sidechat.md`
- `review/supervision-feed.md`
- `review/supervision-status.md`
- `evidence/turn-runtime-evidence.json`
- `evidence/artifact-manifest.json`
- `logs/live-progress-events.jsonl`
- `logs/phase-events.jsonl`

Additional semantic gate requirements:

- cowork-visible supervision text must not fall back to provider round labels
- cowork-visible supervision text must not say `command_run_wait` or other raw
  tool names as the primary activity description
- when waiting on a command or process, supervision should mention the command
  purpose or a safe command summary
- runtime artifacts must still preserve exact command/process detail for
  verbose/debug inspection
- turn runtime and supervision artifacts must agree on the current work story
  without requiring identical wording

## Recommended Implementation Plan

### Phase 1: Replace the old UI contract

- treat this document as the canonical app-facing direction
- drop observation-era naming as a design constraint
- standardize on `TurnEventStream`, `SupervisionView`, and explicit panel view
  models

### Phase 2: Introduce the canonical turn event stream

- build one linear per-turn projection
- unify acceptance runtime transcript, live progress feed, and app runtime
  panel needs behind the same model
- keep exact refs available without forcing them into cowork mode

### Phase 3: Add semantic event enrichment

- classify command, process, tool, and provider activity into user-safe work
  summaries
- produce safe command summaries alongside exact command metadata
- add explicit wait and blocker semantics

### Phase 4: Rebuild supervision on top of semantic inputs

- keep `TurnTodoPlan` and `turn_feed` as primary supervision truth
- let supervision consume semantic hints from the turn event stream
- make sidechat read from semantic supervision state only

### Phase 5: Expose app-facing panel view models

- transcript surface
- runtime panel surface
- supervision panel surface
- artifact / validation surface
- debug surface

### Phase 6: Tighten the `2048` gate

- fail if supervision regresses to low-information runtime labels
- fail if human-visible supervision leaks internal execution vocabulary
- require alignment between runtime evidence and supervision summaries

## Superseded Direction

This revision supersedes the earlier, narrower reading of this file where
supervision was mostly treated as another renderer over loosely defined
progress surfaces.

For app-facing runtime and supervision work:

- do not revive observation-era sidechat wording rules as the primary model
- do not introduce UI-only execution domains
- do not preserve low-information runtime labels for backward compatibility

## Bottom Line

The long-term maintainable shape is:

- one canonical turn event stream for turn-internal chronology
- one canonical supervision view for current-state meaning
- multiple renderers over those projections

That gives us:

- cleaner cowork mode
- richer verbose mode
- better supervision sidechat
- better reuse between acceptance, app UI, and developer diagnostics
