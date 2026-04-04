# Conversation Observation And Supervisor Status

## Purpose

`ConversationObservation` adds a first-class supervision surface for
conversation-scoped runtime work.

It exists so both humans and machine supervisors can ask:

- what this conversation is doing now
- whether it is making progress
- what workflow node or subagent currently owns that work
- whether the run is waiting, blocked, completed, or failed

This feature does not introduce control semantics. It defines the `observe`
half of the supervision surface only.

## Core Model

Observation is a side channel attached to a target conversation.

The durable records are:

- `ConversationObservationSession`
  - one side-session bound to one target conversation
  - records the initiator, responder strategy, and capability snapshot
- `ConversationObservationFrame`
  - one frozen observation anchor per observe exchange
  - stores compact public-id anchors, the frozen bundle snapshot, and the
    canonical assessment payload
- `ConversationObservationMessage`
  - the side-session message history
  - stores the user observation prompt and the observer response

Observation records are not transcript-bearing `Message` rows and never mutate
the target conversation transcript.

## Public Id Rules

All app-facing observation boundaries use public ids only.

This includes:

- target conversation ids
- observation session ids
- observation frame ids
- observation message ids
- workflow run and workflow node refs inside proofs
- subagent-session refs inside proofs

Raw `bigint` ids are rejected at entry boundaries and never appear in response
payloads.

## Observation Exchange

One observation message exchange follows this order:

1. authorize the actor against the target conversation
2. create a `ConversationObservationFrame`
3. persist the side-session user message
4. read the frozen bundle snapshot from the frame
5. run the configured responder
6. persist the observer response message

The frame captures and persists the bounded observation bundle before responder
execution. The responder never re-reads live conversation state for that same
exchange, so the proof surface stays stable even if the target conversation
advances while the answer is being prepared.

## Observation Bundle

The platform assembles a bounded `ObservationBundle` for each frame.

The bundle is conversation-scoped and reuses existing read models instead of
building a second diagnostics subsystem.

### `transcript_view`

Built from the same transcript eligibility rules used by
`Conversations::TranscriptProjection`.

It includes:

- the anchored turn public id when present
- selected input and output message refs when present
- recent transcript-tail items with compact excerpts

### `workflow_view`

Built from the target conversation's current workflow run and node, or the most
recent terminal workflow run when the conversation has already finished.

It includes:

- workflow run public id
- workflow node public id
- node key and node type
- workflow and node lifecycle state
- wait state and wait reason kind
- last transition timestamps

### `activity_view`

Built from `ConversationEvent.live_projection` and limited to compact runtime
event families.

Current observation-facing runtime families include:

- `runtime.workflow_node.*`
- `runtime.agent_task.*`
- `runtime.process_run.*`
- `runtime.tool_invocation.*`

These events carry compact ids and status only. Observation does not persist
raw stdout/stderr chunks or assistant token deltas.

### `subagent_view`

Built from current `SubagentSession` rows attached to the target conversation.

It includes:

- subagent session public ids
- scope and profile metadata
- observed status
- close state

### `diagnostic_view`

Built by reusing `ConversationDiagnostics::RecomputeConversationSnapshot`.

It includes compact execution health facts such as:

- provider round counts
- tool, command, and process counts
- failure counts and recent failure summaries
- usage and cost rollups when available

### `memory_view`

`memory_view` is intentionally minimal in v1.

If no dedicated conversation-scoped short-term memory projection exists, the
bundle returns an empty summary rather than granting the responder general
filesystem or workspace read capability.

## Canonical Assessment

Each observe exchange produces one canonical `ObservationAssessment`.

It is stored on the observation frame and is the system-of-record result for
that exchange.

The assessment includes:

- `observation_session_id`
- `observation_frame_id`
- `conversation_id`
- `overall_state`
- `current_activity`
- `workflow_run_id`
- `workflow_node_id`
- `last_progress_at`
- `stall_for_ms`
- `blocking_reason`
- `recent_activity_items`
- `transcript_refs`
- `proof_refs`
- `proof_text`
- `human_summary`

`overall_state` is normalized to:

- `running`
- `waiting`
- `blocked`
- `completed`
- `failed`

## Result Projections

One canonical assessment yields two outward-facing result projections:

- `supervisor_status`
  - stable machine-readable status for automation and acceptance harnesses
- `human_sidechat`
  - concise human-readable explanation without raw object refs in the text body
  - structured `proof_refs` remain attached alongside the text for grounding

The platform does not run two independent observe passes for these views.
Both projections come from the same frame and the same assessment payload.

## Responder Model

Observation is implemented as the first `EmbeddedAgent` capability.

The current responder strategy is:

- `builtin`

The builtin responder is deterministic and does not require an external model
call. It converts the already-bounded observation bundle into the canonical
assessment, then derives `supervisor_status` and `human_sidechat` from that
same assessment.

`proof_text` remains the internal proof-oriented wording on the assessment.
`human_summary` remains the canonical general-purpose summary on the
assessment. `human_sidechat` is question-aware: it uses the current sidechat
question, the current assessment, and prior sidechat status when available,
while still avoiding workflow or transcript public ids in the visible text.

The architecture keeps a future seam for a program-backed responder, but the
feature does not depend on one.

## Current Integration Surface

Observation is currently integrated as a service-first core surface.

Current internal callers, including the acceptance harness, use:

- `EmbeddedAgents::ConversationObservation::CreateSession`
- `EmbeddedAgents::ConversationObservation::AppendMessage`

Internal scripts and acceptance flows should call those services directly.

The temporary observation-specific `app_api` endpoints remain available as a
legacy bridge, but they are not the primary boundary and should not drive the
long-term product design. A formal product-facing API is still deferred until
user-session authentication and authorization semantics are designed at the
right layer.

The target conversation transcript remains unchanged.

## Supervisor And Acceptance Flow

The Fenix capstone acceptance harness now uses conversation observation as the
in-flight supervision source.

The flow is:

1. create a target conversation and start the workflow run
2. create a conversation observation session through the observation service
3. repeatedly post observation prompts
4. inspect `supervisor_status.overall_state`
5. stop when the run reaches `completed` or `failed`, or when
   `stall_for_ms` breaches the scenario threshold
6. continue with transcript, diagnostics, export/import, and browser
   assertions only after observation reports terminal state

This makes observation, rather than direct database or filesystem inspection,
the supported progress-reporting substrate for long-running coding work.
