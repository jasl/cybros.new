# Core Matrix Conversation Observation Design

## Status

Approved design for the `observe` half of the new conversation supervision
surface.

This document is intentionally destructive-first:

- compatibility is not required
- legacy observation payloads do not need adapters
- schema reset is acceptable when it yields a cleaner model
- historical validation helpers may be replaced instead of preserved

This note covers `observe` only. It does not define `stop`, `steer`, or
`send_message` control semantics. Those remain a separate follow-up design.

## Purpose

Core Matrix already has the durable substrate needed for long-running
agent-driven work:

- `Conversation`, `Turn`, and `WorkflowRun` own execution truth
- `ConversationEvent` is the append-only operational projection layer
- transcript-bearing `Message` rows remain separate from operational events
- `SubagentConnection` already models delegated runtime work

What the platform does not yet have is a first-class way to ask:

- what is this conversation doing right now
- why is it doing that
- what changed most recently
- is it making progress or is it stalled

That gap shows up in two places:

- humans need a side-channel to inspect long-running work
- automated supervisors such as
  the active verification harness described in
  [`verification/README.md`](/Users/jasl/Workspaces/Ruby/cybros/verification/README.md)
  need a supported path for progress inspection instead of reading database rows
  and filesystem artifacts directly

The design target is therefore not a generic diagnostics dump. It is a
bounded, reusable, conversation-scoped observation surface that supports both
human-readable side chat and machine-readable supervision.

## Relationship To Existing Design

This design builds on the current landed behavior in:

- [`human-interactions-and-conversation-events.md`](/Users/jasl/Workspaces/Ruby/cybros/docs/archived-plans/core_matrix-docs-legacy-2026-04-17/behavior/human-interactions-and-conversation-events.md)
- [`workflow-context-assembly-and-execution-snapshot.md`](/Users/jasl/Workspaces/Ruby/cybros/docs/archived-plans/core_matrix-docs-legacy-2026-04-17/behavior/workflow-context-assembly-and-execution-snapshot.md)
- [`subagent-connections-and-execution-leases.md`](/Users/jasl/Workspaces/Ruby/cybros/docs/archived-plans/core_matrix-docs-legacy-2026-04-17/behavior/subagent-connections-and-execution-leases.md)
- [`docs/design/2026-03-26-core-matrix-conversation-close-and-mailbox-control-protocol-design.md`](/Users/jasl/Workspaces/Ruby/cybros/docs/design/2026-03-26-core-matrix-conversation-close-and-mailbox-control-protocol-design.md)
- [`docs/design/2026-04-01-agent-runtime-contract.md`](/Users/jasl/Workspaces/Ruby/cybros/docs/design/2026-04-01-agent-runtime-contract.md)

It preserves these existing boundaries:

- transcript-bearing `Message` rows remain the canonical conversation history
- non-transcript `ConversationEvent` rows remain the operational projection
  surface
- runtime transport streams remain distinct from durable projections
- public or agent-facing boundaries must expose `public_id`, never internal
  `bigint` ids

It changes one important assumption:

- the current transport-only runtime visibility is not sufficient for
  supervision, so the platform now needs a lightweight durable runtime
  observation projection in addition to the temporary Action Cable stream

## Claude Code Reference Findings

Claude Code `/btw` is a useful reference for the side-query shape, but it is
not the target contract.

Relevant findings from
[`references/claude-code-sourcemap/restored-src`](/Users/jasl/Workspaces/Ruby/cybros/references/claude-code-sourcemap/restored-src):

- `/btw` runs on a dedicated side-query pipeline, not on the main conversation
  turn
- it forks an auxiliary responder from the main context snapshot
- the answer does not write back into the main transcript
- tool use is constrained and the flow is single-response
- the side interaction has its own isolated record, not a mutation of the main
  conversation history

Core Matrix should keep the same high-level separation:

- observation is a side channel
- observation does not mutate the target transcript
- observation has its own responder pipeline

Core Matrix intentionally diverges in three ways:

- observation is session-based rather than single-shot
- observation must support machine-readable supervisor output in addition to
  human-readable prose
- observation must expose workflow and subagent state, not just transcript
  context

## Decision Summary

- Introduce `EmbeddedAgents` as a platform-owned home for small, special-purpose
  agent-like capabilities.
- `ConversationObservation` is the first embedded agent in that namespace.
- Observation is modeled as a side session attached to a target conversation,
  not as a new transcript-bearing `Conversation`.
- Each observation turn freezes a lightweight `ConversationObservationFrame`
  that anchors the observed point in time.
- Each observation turn produces one canonical `ObservationAssessment`.
- `supervisor_status` and `human_sidechat` are two projections of the same
  assessment, not two independent observe runs.
- The target conversation transcript is never mutated by observation.
- Observation replies and evidence use `public_id` values at every external
  boundary.
- The observation bundle is bounded and conversation-scoped. It is not a
  general system-inspection shell.
- Long-running supervision uses lightweight durable runtime projection facts,
  not heavy snapshots and not raw transport deltas.
- The acceptance harness should monitor in-flight progress through the
  observation surface before it falls back to post-completion transcript,
  diagnostics, export, and browser validation.

## Embedded Agent Spine

Observation belongs in a reusable platform-owned namespace because it is a
small specialized agent capability rather than ordinary business logic.

Recommended shared application boundary:

```ruby
EmbeddedAgents::Invoke.call(
  agent_key: "conversation_observation",
  actor:,
  target:,
  input:,
  options: {}
)
```

Recommended shared result object:

- `status`
- `output`
- `metadata`
- `audit_payload`
- `responder_kind`

Recommended service layout:

```text
core_matrix/app/services/embedded_agents/
  invoke.rb
  registry.rb
  result.rb
  responder_registry.rb
  errors.rb

core_matrix/app/services/embedded_agents/conversation_observation/
  invoke.rb
  authority.rb
  create_session.rb
  append_message.rb
  build_frame.rb
  build_bundle.rb
  build_assessment.rb
  route_responder.rb
  responders/
    builtin.rb
    agent_contract.rb
```

The spine is intentionally small. It standardizes invocation and responder
routing. It does not force every embedded agent to share one generic session or
message table.

## Domain Model

### `ConversationObservationSession`

Purpose:

- binds one side-channel observation session to one target conversation
- tracks who initiated the session
- declares responder and capability policy
- owns the observation-side message history

Recommended fields:

- `installation_id`
- `public_id`
- `target_conversation_id`
- `initiator_type`
- `initiator_id`
- `lifecycle_state`
- `responder_strategy`
- `capability_policy_snapshot`
- `last_observed_at`
- timestamps

Rules:

- a session belongs to exactly one target conversation
- a session never owns transcript-bearing `Message` rows on the target
  conversation
- session APIs expose the target conversation through `Conversation.public_id`

### `ConversationObservationMessage`

Purpose:

- stores the side-channel conversation history
- records the user question and the observer response
- points both halves of one observation exchange at the same frame

Recommended fields:

- `installation_id`
- `public_id`
- `conversation_observation_session_id`
- `conversation_observation_frame_id`
- `role`
  - `user`
  - `observer_agent`
  - `system`
- `content`
- `metadata`
- timestamps

Rules:

- user message and observer response from the same exchange share one frame
- observation messages stay inside the observation session; they do not enter
  the target conversation transcript

### `ConversationObservationFrame`

Purpose:

- freezes the minimal anchor describing what point in the target conversation
  was observed
- stores the canonical lightweight assessment output for that exchange

Recommended fields:

- `installation_id`
- `public_id`
- `conversation_observation_session_id`
- `target_conversation_id`
- `anchor_turn_id`
- `anchor_turn_sequence_snapshot`
- `conversation_event_projection_sequence_snapshot`
- `active_workflow_run_id`
- `active_workflow_node_id`
- `wait_state`
- `wait_reason_kind`
- `active_subagent_connection_ids`
- `runtime_state_snapshot`
- `assessment_payload`
- timestamps

Rules:

- the frame stores ids and compact status only
- the frame does not store transcript copies, full workflow graphs, or raw
  runtime deltas
- the frame anchor is frozen once, before responder execution
- response generation must not recompute the anchor after the target
  conversation advances

## Observation Assessment

Each observe exchange produces one canonical `ObservationAssessment`. This is
the system-of-record result for that frame.

Recommended shape:

- `observation_session_id`
- `observation_frame_id`
- `target_conversation_id`
- `overall_state`
  - `running`
  - `waiting`
  - `blocked`
  - `completed`
  - `failed`
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
- `metadata`

Projection rules:

- `supervisor_status` is the structured machine-readable projection
- `human_sidechat` is the human-readable explanation derived from the same
  assessment
- both projections must cite the same `proof_refs`
- the acceptance harness consumes `supervisor_status`
- humans and logs may retain `human_sidechat` as proof text

This avoids two independent observe executions returning slightly different
claims about the same underlying runtime state.

## Observation Surface

Observation is not a generic read-only shell. The platform builds a bounded
conversation-scoped `ObservationBundle` and passes it to the responder.

### `transcript_view`

Purpose:

- answer questions about what the conversation has already said
- support proof snippets for supervisor and human readers

Contents:

- current anchor turn public id
- selected input and output message public ids when present
- recent transcript tail with compact excerpts
- transcript references suitable for proof citations

Rules:

- uses transcript-bearing messages only
- does not inject `ConversationEvent` rows into canonical transcript context

### `workflow_view`

Purpose:

- expose the active execution path during long-running work

Contents:

- active workflow run public id
- active workflow node public id
- active node key and type
- workflow lifecycle state
- wait state
- wait reason kind
- blocking resource public id when present
- last transition timestamp
- elapsed running time

### `activity_view`

Purpose:

- expose in-flight progress without requiring transcript completion

Contents:

- recent lightweight runtime activity items
- recent workflow-node state changes
- recent tool or subagent state changes
- most recent progress heartbeat

Rules:

- uses lightweight durable projection facts, not raw output streams
- does not store stdout or token-by-token assistant deltas

### `subagent_view`

Purpose:

- explain delegated work

Contents:

- active subagent connection public ids
- scope
- profile key
- observed status
- close state
- parent/owner relationships expressed via public ids

### `diagnostic_view`

Purpose:

- summarize execution health

Contents:

- provider round counts
- tool, command, and process counts
- failure counts
- recent failure summary
- usage and cost summary when available

### `memory_view`

Purpose:

- allow responder reasoning over conversation-scoped short-term execution state

Contents:

- conversation-scoped short-term memory summaries only

Rules:

- no unrestricted filesystem reads
- no workspace-global search
- no durable transcript mutation

## Lightweight Runtime Projection

Current runtime transport is useful for UI latency, but it is not durable
enough for supervision. Observation therefore needs a small durable runtime
projection layer.

The design should extend `ConversationEvent` rather than introduce a second
runtime-ledger model.

Recommended event families:

- `runtime.workflow_run.state_changed`
- `runtime.workflow_node.entered`
- `runtime.workflow_node.state_changed`
- `runtime.wait_state.changed`
- `runtime.subagent_connection.state_changed`
- `runtime.tool_activity.changed`
- `runtime.progress_heartbeat`

Recommended event characteristics:

- append-only rows
- replace-in-place live-projection behavior through `stream_key` and
  `stream_revision` where appropriate
- compact payloads with ids and current status only
- no raw stdout/stderr chunk persistence
- no token-delta persistence for assistant output

This keeps runtime visibility lightweight while still letting observation
answer mid-turn progress questions from durable facts.

## Responder Model

Observation should not route back through the target conversation's main agent
loop. The observed worker is the subject of observation, not the canonical
observer.

Recommended responder kinds:

- `builtin`
  - platform-owned observer implementation
- `agent_contract`
  - a dedicated responder method on an `AgentDefinitionVersion`

The responder contract is separate from ordinary turn execution.

Recommended protocol method:

- `conversation_observe_answer`

Recommended request payload:

- `request_kind`
- `observation_session_id`
- `observation_frame_id`
- `target`
  - `conversation_id`
  - `anchor_turn_id`
  - `anchor_turn_sequence`
- `initiator`
  - `kind`
  - `id`
- `profile`
  - `supervisor_status`
  - `human_sidechat`
- `question`
- `observation_bundle`

Recommended response payload:

- `status`
  - `answered`
  - `insufficient_context`
  - `rejected`
- `assessment`
- `supervisor_status`
- `human_sidechat`
- `citations`
- `metadata`

The `assessment` is canonical. The two projection payloads are convenience
views over the same core result.

## API Shape

The app-facing observation surface should be session-based because humans and
automated supervisors both need repeated questioning over the same target
conversation.

Recommended app-facing resources:

- `POST /app_api/conversation_observation_sessions`
- `GET /app_api/conversation_observation_sessions/:id`
- `GET /app_api/conversation_observation_messages`
- `POST /app_api/conversation_observation_messages`

Recommended creation shape:

- target conversation public id
- initiator actor derived from the authenticated caller
- optional responder strategy override when policy allows it

Recommended message-append result:

- `method_id`
- `observation_session_id`
- `observation_frame_id`
- `target_conversation_id`
- `assessment`
- `supervisor_status`
- `human_sidechat`

The API stays app-facing. It does not expose internal `bigint` ids and does not
require callers to read database tables directly.

## Supervisor Status Contract

The acceptance harness needs a stable contract that can answer: keep waiting,
fail early, or proceed to final verification.

Recommended `supervisor_status` shape:

- `observation_session_id`
- `observation_frame_id`
- `target_conversation_id`
- `overall_state`
  - `running`
  - `waiting`
  - `blocked`
  - `completed`
  - `failed`
- `current_activity`
- `workflow_run_id`
- `workflow_node_id`
- `workflow_node_key`
- `workflow_node_type`
- `wait_state`
- `wait_reason_kind`
- `blocking_resource_id`
- `last_progress_at`
- `stall_for_ms`
- `recent_activity_items`
- `latest_transcript_excerpt`
- `completion_assessment`
- `proof_refs`

Every identifier in this payload must be a `public_id`.

`proof_refs` should prefer stable public references such as:

- target conversation public id
- target turn public id
- workflow run public id
- workflow node public id
- selected message public ids
- subagent connection public ids
- conversation event stream keys when useful

## Verification Harness Integration

The capstone verification harness should change its in-flight supervision path.

Current direction:

- wait directly on `AgentTaskRun` and `WorkflowRun` terminal state
- inspect database-backed status helpers
- perform transcript and export validation after completion

New direction:

1. create an observation session for the target conversation
2. periodically append a supervisor observation message
3. read `supervisor_status`
4. decide whether the run is:
   - making progress
   - waiting on an expected blocker
   - stalled or blocked
   - terminal
5. only after terminal state continue to transcript, diagnostics, export, and
   browser validation

This means
the active verification harness
[`verification/README.md`](/Users/jasl/Workspaces/Ruby/cybros/verification/README.md)
acts as a supported supervisor client rather than as an implementation-aware
database and filesystem observer for in-flight progress.

Post-completion transcript, diagnostics, export/import, and host verification
remain valid verification steps. The change here is specifically about how
progress is observed before completion.

## Authority Model For Observe

Observation authority is independent from ordinary conversation addressability.

Examples:

- the workspace owner may observe their own active conversation
- an authorized teammate may observe another user's active conversation without
  being able to control it
- a supervisor agent may observe target conversations through policy grants

Recommended policy inputs:

- installation ownership
- workspace membership
- target conversation visibility
- explicit observation grants
- responder-strategy restrictions

This design intentionally does not define control authority. Control follows in
the later `control` design note.

## Relationship To Existing `agent_observation` Tool Kind

Core Matrix already uses `agent_observation` as a tool-kind category for
capabilities such as `subagent_wait` and `subagent_list`.

`ConversationObservation` should not be reduced to just another ordinary tool
call. It is a platform-owned embedded agent with its own session model and app
API.

The relationship should be:

- `agent_observation` remains the runtime capability category for observation
  tools visible to agents
- `ConversationObservation` is the higher-level platform feature for side-band
  supervision
- future reserved tools such as `core_matrix__observe_expand` may reuse the
  same bundle and authority logic when a responder truly needs bounded
  expansion

## Layering

Presentation layer:

- app-facing controllers for observation sessions and messages

Application layer:

- `EmbeddedAgents::Invoke`
- `EmbeddedAgents::ConversationObservation::*`

Domain layer:

- `ConversationObservationSession`
- `ConversationObservationMessage`
- `ConversationObservationFrame`
- authority rules
- assessment shape

Infrastructure layer:

- transcript projections
- conversation-event live projection reads
- workflow and subagent read models
- responder transport to builtin or agent-backed implementations

The lower layers must not depend on the app-facing controller layer.

## Failure Modes

- observation session creation rejects unauthorized actors
- observation APIs reject internal ids at app and agent boundaries
- observation never writes transcript-bearing `Message` rows to the target
  conversation
- observation never treats transport-only assistant output as durable proof
- stalled runs do not masquerade as active progress when no recent activity
  event or progress heartbeat exists
- supervisor status and proof text do not diverge because they derive from the
  same canonical assessment
- observation bundle assembly must tolerate missing optional surfaces such as
  empty memory summaries or zero active subagent connections

## Implementation Notes

The first implementation should favor the smallest end-to-end slice that proves
the contract:

1. embedded-agent invocation spine
2. observation session, frame, and message models
3. app-facing observation endpoints
4. builtin observation responder
5. lightweight runtime projection additions on `ConversationEvent`
6. acceptance-harness migration to `supervisor_status`

Program-backed responders can follow once the builtin path is stable.

## Follow-Up Documents

After implementation lands, these documents should be updated or added:

- a product or design note under `core_matrix/docs/` or `docs/design/`
  describing landed conversation observation behavior
- a behavior update describing the new durable lightweight runtime projection
- a follow-up `control` design note covering stop, steer, and send-message
  semantics
