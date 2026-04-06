# Fenix App UI Contract

## Goal

Define one canonical UI event contract for `Fenix` that can power two
presentation styles without splitting the underlying data model:

- `Cowork mode` as the default product style, closer to `Claude Code` /
  `Claude Cowork`
- `Verbose mode` as an alternate product style, closer to `Codex`

The key rule is simple:

- one runtime event model
- multiple renderers

The app should not invent a second execution-state domain just to support a
different visual style.

## Product Decision

The default app style should be `Cowork mode`.

That means:

- the main conversation stays relatively clean
- work is explained in terms of current focus, progress, blockers, and next
  steps
- runtime details remain available, but they live in dedicated panels rather
  than flooding the main transcript

At the same time, the app should support a `Verbose mode` for developer-facing
inspection:

- more inline tool and runtime visibility
- more Codex-like "what happened this turn" storytelling
- easier debugging without changing the backend model

## Design Inputs

This contract is grounded in the acceptance bundle that the `2048` capstone now
produces.

Current canonical bundle surfaces:

- bundle entry point and layout contract:
  [acceptance/README.md](/Users/jasl/Workspaces/Ruby/cybros/acceptance/README.md)
- review transcript projection:
  [turn_runtime_transcript.rb](/Users/jasl/Workspaces/Ruby/cybros/acceptance/lib/turn_runtime_transcript.rb)
- live runtime feed projection:
  [live_progress_feed.rb](/Users/jasl/Workspaces/Ruby/cybros/acceptance/lib/live_progress_feed.rb)
- organized bundle layout:
  [artifact_bundle.rb](/Users/jasl/Workspaces/Ruby/cybros/acceptance/lib/artifact_bundle.rb)

The app contract should line up with the same artifact families:

- `review/`
- `evidence/`
- `logs/`
- `exports/`
- `playable/`
- `tmp/`

## UI Surface Model

The app should be built from five product surfaces.

### 1. Main Transcript

This is the user-facing conversation.

It should show:

- user messages
- main-agent replies
- short work summaries
- explicit asks for approval or clarification
- major state transitions when they matter to the user

It should not default to rendering every tool call or every workflow node.

### 2. Turn Runtime Panel

This is the "what happened inside this turn" surface.

It should show:

- phase-by-phase execution
- main-agent runtime progress
- subagent progress lanes
- tool and command activity summaries
- host validation milestones
- supervision snapshots when they materially change the story

This is the closest app surface to the current
`review/turn-runtime-transcript.md`.

### 3. Supervision Panel

This is the "what does the system think is happening right now" surface.

It should show:

- current focus
- blocker and waiting summaries
- active subagents
- feed entries
- sidechat answers
- stable plan-driven status once the todo-plan work lands

This is powered by the existing supervision projections, not by ad hoc
transcript parsing.

### 4. Side Panels

These panels should surface adjacent task state without polluting the main
conversation:

- subagent list
- changed files
- artifacts
- export/debug-export bundle access
- playable preview / verification results

### 5. Debug Panel

This is a developer-facing surface.

It should show:

- raw runtime evidence
- tool payload references
- workflow node keys
- command and process metadata
- acceptance/debug-export links

This panel can feel more like Codex or internal ops tooling.

## Canonical Event Model

Every render mode should be derived from the same canonical event model.

### Shared Fields

Every runtime event projection should support these fields where applicable:

- `timestamp`
- `conversation_public_id`
- `turn_public_id`
- `actor_type`
- `actor_label`
- `actor_public_id`
- `phase`
- `kind`
- `status`
- `summary`
- `detail`
- `source_refs`

Execution-linked events may additionally carry:

- `workflow_run_public_id`
- `workflow_node_key`
- `workflow_node_ordinal`
- `node_type`
- `tool_invocation_public_id`
- `command_run_public_id`
- `process_run_public_id`

The important rule is that these fields belong to the evidence model even if a
particular renderer chooses not to display all of them.

### Actor Lanes

The UI should treat runtime progress as a lane-based event stream.

Minimum lane types:

- `main_agent`
- `subagent`
- `supervisor`
- `host_validator`
- `acceptance_harness`

Lane labels should be human-readable:

- `main`
- `researcher#1`
- `reviewer#1`
- `supervisor`
- `host`

This is already aligned with the current acceptance projections.

### Event Families

The canonical model should support these event families:

1. `conversation_message`
   - user or assistant transcript message
2. `runtime_progress`
   - phase changes
   - workflow node state changes
   - provider round progression
3. `tool_activity`
   - tool invocation summaries
   - command execution summaries
   - process lifecycle summaries
4. `subagent_progress`
   - session start
   - current status
   - progress summary
   - completion
5. `supervision_update`
   - current focus
   - feed updates
   - sidechat-relevant snapshots
6. `host_validation`
   - install/build/test/preview/playwright milestones
7. `artifact_update`
   - export/debug-export/report availability

Not every family belongs in every panel.

## Rendering Contract

## Cowork Mode

This is the default app style.

### Main Transcript

Render:

- user messages
- assistant messages
- concise "work summary" rows
- explicit approvals/questions
- final delivery summaries

Collapse or redirect:

- raw tool payloads
- most workflow node churn
- repeated provider-round activity

### Runtime Panel

Render:

- turn timeline
- lanes by actor
- grouped phases
- tool activity summaries
- subagent progress
- host validation checkpoints

Default view:

- grouped by `Plan`, `Build`, `Validate`, `Deliver`
- concise summaries first
- expandable details

### Supervision Panel

Render:

- live focus
- active subagents
- waiting/blocker state
- recent feed
- sidechat transcript

### Side Panels

Render:

- files changed
- artifacts available
- playable proof
- subagent roster

## Verbose Mode

This is the developer and inspection style.

### Main Transcript

Allow more inline runtime detail:

- "explored files"
- "ran command"
- "spawned researcher#1"
- "edited file"

It should feel closer to Codex without changing the underlying event model.

### Runtime Panel

Show more of the raw event stream:

- more workflow-node detail
- more command/process steps
- finer tool summaries

### Debug Panel

Always available in verbose mode, but still separate from the main transcript.

## Event Placement Rules

The same event can exist in evidence without appearing in every surface.

### Main Transcript Only

- user messages
- assistant-facing explanations
- approvals/questions
- final answer / delivery handoff

### Runtime Panel Only

- provider round progression
- tool summaries
- command/process activity
- subagent runtime progress
- host validation milestones

### Supervision Panel Only

- sidechat
- supervision feed
- current focus / blocked / waiting state

### Debug Only

- raw ids and payload references
- exact workflow node keys
- low-level evidence joins

## Acceptance Gate

The `2048` capstone should prove that the app has enough substrate to support
both render modes.

Minimum required artifacts:

- `review/conversation-transcript.md`
- `review/turn-runtime-transcript.md`
- `review/supervision-sidechat.md`
- `review/supervision-feed.md`
- `review/supervision-status.md`
- `evidence/turn-runtime-evidence.json`
- `evidence/artifact-manifest.json`
- `logs/live-progress-events.jsonl`
- `logs/phase-events.jsonl`

These do not have to be the final app payloads, but the app contract is not
credible unless this bundle can already be projected into:

- a clean cowork transcript
- a verbose runtime timeline
- a supervision panel
- side panels for artifacts and playable proof

## Mapping From Current Acceptance Outputs

Current acceptance outputs already map cleanly to the target app surfaces:

- `review/conversation-transcript.md`
  - main transcript baseline
- `review/turn-runtime-transcript.md`
  - cowork runtime panel baseline
- `evidence/turn-runtime-evidence.json`
  - verbose/debug evidence baseline
- `logs/live-progress-events.jsonl`
  - live runtime feed baseline
- `review/supervision-feed.md`
  - supervision activity baseline
- `review/supervision-sidechat.md`
  - supervision conversation baseline
- `review/supervision-status.md`
  - current-focus/status baseline
- `playable/`
  - playable-result panel baseline

## Non-Goals

- do not create separate persistence models just to support different UI skins
- do not make the acceptance markdown files themselves the product API
- do not flatten all subagent and tool activity into the main conversation by
  default
- do not force the verbose style as the only style

## Next Steps

1. Keep the canonical runtime event model stable.
2. Promote the current acceptance projections into explicit app-facing view
   models.
3. Let the app switch between:
   - `Cowork mode`
   - `Verbose mode`
4. Keep using the `2048` capstone as the product gate for UI-readiness.
