# Conversation Execution Runtime Handoff Research Note

## Status

Recorded research for future `Core Matrix` workbench handoff planning.

This note captures durable conclusions about conversation-level execution
runtime handoff, current `Core Matrix` constraints, and low-regret data-model
guidance. It should remain useful even if local `references/` code changes
later.

Update on 2026-04-13:

- the execution-epoch redesign described by this research has now been adopted
  in `core_matrix`
- implementation was done as a destructive base-schema rewrite, not as an
  additive transition migration
- references below that argue "no immediate schema change is required" should
  now be read as historical context rather than current guidance

## Decision Summary

- Treat a conversation-level execution-runtime change as a real handoff between
  execution epochs, not as a cheap metadata update.
- Keep runtime ownership on `Turn` and frozen execution snapshots; do not add a
  mutable `conversations.current_execution_runtime_id` as a shortcut.
- Preserve the current product rule that runtime selection is creation-scoped
  until a dedicated handoff flow exists.
- If handoff ships later, implement it as a durable operation with explicit
  quiesce, cutover, and recovery states rather than as one long database
  transaction.
- Current export/import and runtime-event infrastructure are useful building
  blocks, but they do not yet provide Claude-style remote bootstrap and resume.
- A future handoff operation should build on the execution-epoch model rather
  than replacing it.
- Future pre-work should now focus on additive operation tables such as
  `conversation_handoff_operations`, not on re-litigating runtime ownership.

## Current Core Matrix Facts

### Runtime Selection Is Intentionally Creation-Scoped

Current product docs are explicit:

- workspace policy owns the default execution runtime for new conversations
- the first turn may override that runtime
- follow-up message APIs must not switch runtime
- a dedicated handoff API is future work

This is implemented in the app surface today:

- `POST /app_api/conversations` accepts `agent_id` plus an optional
  `execution_runtime_id`
- `POST /app_api/conversations/:id/messages` rejects follow-up runtime changes
  with `conversation_runtime_handoff_not_implemented`

The resulting product behavior is deliberate, not an accidental gap.

### Conversation Owns Current Execution Continuity

The redesign now makes continuity explicit:

- `Conversation` owns the current execution boundary through
  `current_execution_epoch_id`
- `Conversation` caches `current_execution_runtime_id` for hot-path reads
- `Turn` still freezes the chosen runtime and runtime version on the turn row

That means the current code now treats responsibilities like this:

- `Conversation` owns thread identity, lifecycle, supervision, lineage, and
  current execution continuity
- `ConversationExecutionEpoch` is the durable source of truth for continuity
  boundaries
- `Turn` belongs to `execution_epoch` plus optional `execution_runtime` and
  `execution_runtime_version` snapshots
- `ExecutionContract` exposes runtime identity as part of the frozen turn task
  identity
- `ProcessRun` validates that its epoch and runtime match the owning turn

This means future handoff should create a new execution epoch in the same
conversation timeline rather than mutate one canonical runtime field on the
conversation row.

### Follow-Up Turns Continue From The Current Execution Epoch

`Turns::SelectExecutionRuntime` resolves runtime in this order:

1. explicit request
2. conversation current runtime cache
3. workspace default runtime
4. agent default runtime

Because ordinary follow-up message APIs no longer allow explicit runtime
selection, existing conversations effectively continue on the runtime pinned by
their current execution epoch.

This is an important continuity rule:

- runtime identity is already treated as part of thread continuity
- changing runtime mid-conversation would be a semantic cutover, not a benign
  option change

### Current Locking Is Short-Lived And Entry-Focused

`Turns::StartUserTurn` uses the shared conversation mutation lock before
appending a new turn. That lock is good for short critical sections such as:

- validating the conversation is still mutable
- resolving the turn execution identity
- allocating the next turn sequence
- creating the selected input message

It is not a good fit for a future handoff flow that may need:

- quiescing active work
- exporting transcript or runtime context
- bootstrapping remote execution
- resuming or hydrating results

That kind of work needs a durable operation record rather than one long-held
row lock or one long transaction.

### Runtime Connectivity Is Runtime-Scoped, Not Conversation-Scoped

`ExecutionRuntimeConnection` models the active connection for one execution
runtime and enforces at most one active connection per runtime. It does not
model a conversation-scoped remote session.

That is a useful base abstraction, but it is not enough for Claude-style
teleport semantics, where the system also needs a conversation-specific remote
bootstrap or resume unit.

### Export And Import Already Exist, But Import Creates A New Conversation

`ConversationExports::BuildConversationPayload` can export transcript-bearing
messages and attachments.

`ConversationBundleImports::RehydrateConversation` can re-create that transcript,
but it always materializes a new conversation and rehydrates turns into that
new thread using the target agent's default runtime.

That is useful for portability and debugging, but it is not yet a "resume the
same conversation in another runtime" path.

### Runtime Event Streaming Already Exists

The app surface already has:

- realtime runtime-event broadcasts for a conversation
- `conversation_turn_runtime_event_list` for timeline reconstruction

This is a strong foundation for future handoff UX, because users will need to
see:

- quiescing state
- export/bootstrap progress
- remote execution progress
- completion or failure details

What is missing is the handoff lifecycle itself, not the entire event system.

## Reference Product Summary

These reference products are supporting material only. They are not the source
of truth for `Core Matrix`.

### Codex

The local Codex reference suggests that "Continue in Cloud" is closer to
"submit current work as a new remote task in a selected cloud environment" than
to literal process migration.

Durable pattern:

- choose a target environment
- package the task, branch, and optional diff/context
- create a new cloud task
- observe the remote task from the original client

This is still a handoff in product terms, but it behaves more like cutover to a
new remote execution slot than resuming the same local process.

### Claude Code

Claude has two distinct patterns:

- `remote-control`, which exposes an existing local session to another client
- `teleport`, which bootstraps or resumes a cloud session with repo transfer and
  transcript hydration

The second pattern is the closer comparison for `Conversation`-level
runtime-to-remote handoff.

Durable Claude-style behaviors:

- explicit remote session bootstrap
- repo or workspace transfer into the remote environment
- resume or hydration path back into the client-visible thread
- visible lifecycle around switching to remote execution

### OpenCode

The local OpenCode reference does not show a comparable cloud handoff flow. Its
session continuation semantics are still local-sandbox or worktree oriented.

Conclusion:

- `Core Matrix` runtime handoff, if built, is much closer to Claude teleport
  than to OpenCode's existing continuation model

## Consequences For Future Handoff Design

### Handoff Should Be A Dedicated Operation

Future handoff should not be piggybacked on follow-up message creation.

It needs an explicit operation with durable state, likely parallel in shape to
`ConversationCloseOperation`, because the system will need to model at least:

- requested
- quiescing
- bootstrapping
- awaiting remote readiness
- cutover completed
- failed or degraded

### Handoff Should Quiesce Before Cutover

Because runtime identity is frozen on the turn and enforced by downstream
resources, a handoff should not try to hot-swap an already active turn from one
runtime to another.

Safer mental model:

- finish or interrupt the active execution epoch
- establish the next runtime target
- start the next execution epoch under that runtime

This preserves current invariants instead of working around them.

### Handoff Should Not Be One Long Database Transaction

The transaction boundary should cover only immediate state transitions and
operation-record updates.

Slow external steps should happen outside that short transaction window:

- export or bundle assembly
- remote bootstrap calls
- waiting for remote readiness
- remote resume or hydration

### The User-Facing Thread Can Stay Stable

Nothing in the current model forces a future handoff to fork to a different
conversation id.

Because `Conversation` already acts as the durable user-facing thread container
while `Turn` owns the frozen execution identity, future handoff can remain
append-only:

- same conversation
- later turns freeze the new runtime
- handoff operation records the boundary between epochs

That is a better fit than retroactively mutating older turns or re-binding the
whole conversation row to a new runtime id.

## Data-Model Guidance

### Changes That Are Not Recommended Now

Do not preemptively add these:

- `conversations.execution_runtime_id`
- `conversations.execution_runtime_version_id`
- follow-up message support that mutates runtime in place
- any "current runtime" field whose only job is to disagree with historical
  turn reality

Reasons:

- it would conflict with the approved rule that `Conversation` does not own the
  current execution runtime
- it would make existing frozen-turn semantics harder to reason about
- it would create migration and reconciliation work later when handoff needs
  epoch boundaries anyway

### Low-Regret Additive Shapes If Pre-Work Becomes Necessary

If the product later decides to prepare for handoff before the full feature is
implemented, the safest additive shapes are:

- a dedicated `conversation_handoff_operations` table
- an explicit execution-epoch concept recorded either on turns or derivable
  from handoff operations
- handoff lifecycle events added to the existing conversation runtime stream

Recommended shape for a future handoff operation:

- source runtime id and version id
- target runtime id and version id
- requested-by actor
- lifecycle state
- result payload
- failure payload
- requested, started, and completed timestamps

Important constraint:

- this should be additive beside current conversation and turn data, not a
  rewrite of existing ownership

### Immediate Recommendation

No schema migration is currently required just to keep future handoff viable.

The current model is already future-friendly because:

- turns are append-only
- runtime identity is frozen per turn
- the app surface already rejects unsafe runtime switching
- existing export and event infrastructure can be extended later

In other words, the cheapest path today is to keep the current invariants
stable rather than trying to guess the final handoff schema too early.

## Re-Evaluation Triggers

Re-open this note when one of these becomes true:

- the app surface wants a user-visible "continue in cloud" or "switch runtime"
  action inside an existing conversation
- a remote runtime must resume the same conversation instead of importing into a
  new one
- runtime cutover must preserve supervision and transcript continuity inside one
  thread
- the product wants observable handoff progress or failure in the workbench

## Reference Index

These references informed the note, but they are not the source of truth.

Current `Core Matrix` references:

- `/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-04-12-ssr-first-workbench-and-onboarding-design.md`
- `/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-04-12-ssr-first-workbench-and-onboarding.md`
- `/Users/jasl/Workspaces/Ruby/cybros/docs/finished-plans/2026-04-03-agent-execution-runtime-reset-design.md`
- `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/docs/behavior/turn-entry-and-selector-state.md`
- `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/controllers/app_api/agent_conversations_controller.rb`
- `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/controllers/app_api/conversation_messages_controller.rb`
- `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/workbench/create_conversation_from_agent.rb`
- `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/workbench/send_message.rb`
- `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/turns/select_execution_runtime.rb`
- `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/turns/start_user_turn.rb`
- `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/conversations/with_mutable_state_lock.rb`
- `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/models/turn.rb`
- `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/models/execution_contract.rb`
- `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/models/process_run.rb`
- `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/models/execution_runtime.rb`
- `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/models/execution_runtime_connection.rb`
- `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/conversation_exports/build_conversation_payload.rb`
- `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/conversation_bundle_imports/rehydrate_conversation.rb`
- `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/conversation_runtime/build_app_event.rb`
- `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/controllers/app_api/conversation_turn_runtime_events_controller.rb`

Supporting local reference-product paths:

- `/Users/jasl/Workspaces/Ruby/cybros/references/original/references/codex/codex-rs/cloud-tasks-client/src/http.rs`
- `/Users/jasl/Workspaces/Ruby/cybros/references/original/references/codex/codex-rs/cloud-tasks/src/lib.rs`
- `/Users/jasl/Workspaces/Ruby/cybros/references/claude-code-sourcemap/restored-src/src/bridge/createSession.ts`
- `/Users/jasl/Workspaces/Ruby/cybros/references/claude-code-sourcemap/restored-src/src/utils/teleport.tsx`
- `/Users/jasl/Workspaces/Ruby/cybros/references/original/references/opencode/packages/app/src/components/session/session-new-view.tsx`
