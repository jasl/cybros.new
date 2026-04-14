# Live Supervision Sidechat Design

## Goal

Restore the **real** supervision sidechat acceptance contract:

- while a conversation turn is still active or waiting, an operator can ask the
  agent what it is doing now
- the reply is grounded in the current frozen supervision snapshot
- the reply does not collapse into a post-hoc terminal summary
- the sidechat exchange is visible through app-facing APIs, debug export, and
  human-readable review artifacts

This follow-up intentionally separates two concerns that were previously mixed:

1. **artifact integrity**
   - capstone should still prove that review/export surfaces include supervision
     transcript material when a probe exists
2. **live-progress semantics**
   - a dedicated acceptance scenario should verify that sidechat works during an
     in-flight turn and reports current progress/blockers

## Current Problem

The branch already restored supervision transcript export and review rendering
inside the 2048 capstone. That fixed a real regression in artifact visibility,
but the current probe happens only **after** the main turn has already reached a
terminal state.

That means the capstone currently proves:

- supervision sessions/messages can still be created
- sidechat transcript is exported and rendered

But it does **not** prove:

- sidechat works while work is still in progress
- sidechat answers current work / blocker / recent progress
- the frozen supervision snapshot is useful during a long-running turn

The product contract in
[`conversation-supervision-and-control.md`](/Users/jasl/Workspaces/Ruby/cybros/core_matrix/docs/behavior/conversation-supervision-and-control.md)
is stronger than the current capstone probe:

- sidechat is a human interaction surface over frozen supervision snapshots
- it can answer current work, recent progress, blockers, next steps, and child
  task state

## Desired Contract

After this follow-up:

- the existing 2048 capstone keeps its current post-turn supervision probe for
  export/review coverage
- a new hybrid acceptance scenario exercises **live** supervision sidechat
  during an active/waiting turn
- that scenario must use app_api supervision endpoints, not internal shortcut
  helpers, for session/message creation
- the scenario must verify that the answer reflects in-flight work rather than
  terminal work
- the scenario must export the conversation while the turn is still in a live
  wait state and confirm the supervision transcript survives export

## Recommended Approach

### 1. Keep capstone narrow

Do **not** turn the 2048 capstone into a timing-sensitive “ask while coding”
scenario.

The capstone’s primary purpose remains:

- app-facing roundtrip
- runtime execution
- export/debug export
- generated-host validation
- playability proof

Keeping its supervision probe post-turn is acceptable because that probe is now
about artifact completeness, not live-progress semantics.

### 2. Add a dedicated hybrid acceptance scenario for live sidechat

Add a new acceptance scenario that:

- deterministically creates a conversation with a stable in-flight wait state
- uses app_api supervision endpoints to create a supervision session
- posts a sidechat question while the turn is still active/waiting
- verifies the answer is about current work / blocker / recent progress
- verifies the exchange is persisted and exportable

The scenario should be `hybrid_app_api`, not `app_api_surface`, because there is
still no product-facing endpoint that deterministically creates the specific
waiting workflow shape needed for stable acceptance coverage.

Internal setup is acceptable only for:

- the deterministic active/waiting workflow substrate

App API must be used for:

- supervision session create
- supervision message append
- supervision message list
- debug export

### 3. Use a deterministic waiting state, not a terminal turn

The most stable live-sidechat target is a deterministic conversation that is
already waiting on a human interaction or similar blocker.

That state is preferable to “long provider run in flight” because:

- it avoids timing races
- it keeps current-turn semantics alive
- it still exercises the exact product promise: asking what the agent is doing
  or waiting on during active work

The scenario should assert a response like:

- “Right now the conversation is waiting …”
- or equivalent current-status language

It must **not** accept an answer that is merely:

- “Most recently, execution runtime completed …”

### 4. Add app_api helpers for supervision endpoints

Acceptance currently has internal helpers:

- `create_conversation_supervision_session!`
- `append_conversation_supervision_message!`

Those are useful for low-level tests, but the new acceptance scenario should use
app_api wrappers instead:

- `app_api_create_conversation_supervision_session!`
- `app_api_append_conversation_supervision_message!`
- `app_api_conversation_supervision_messages!`

This keeps the acceptance boundary honest and aligned with the public product
surface.

### 5. Export the live sidechat transcript

The new scenario should produce a debug export **before** resolving the wait
state, then verify:

- `conversation_supervision_sessions.json` contains the session
- `conversation_supervision_messages.json` contains both user and supervisor
  messages
- the transcript content reflects current waiting/progress semantics

This is the durable proof that live-sidechat survives export even when the turn
has not yet completed.

## Alternatives Considered

### A. Make 2048 capstone itself ask during generation

Rejected.

It would make the capstone more timing-sensitive, harder to debug, and less
focused. The 2048 scenario should stay a broad roundtrip proof, not become the
only place that verifies supervision live-progress semantics.

### B. Only add more service/request tests

Rejected.

Service and request tests already prove much of the snapshot semantics. What is
missing is an end-to-end acceptance proof that:

- a live in-flight conversation can be interrogated through app_api
- the persisted sidechat transcript survives export/review

### C. Replace the post-turn capstone probe with a live probe

Rejected.

That would conflate two different concerns and lose the explicit artifact
coverage now provided by the capstone.

## Risks

### Acceptance race if the scenario uses a transient running state

Mitigation:

- use a deterministic waiting state, not a narrowly timed transient running
  step

### Acceptance drifts back to internal shortcuts

Mitigation:

- add app_api helpers
- register the scenario as `hybrid_app_api`
- keep contract coverage that forbids obsolete helper shortcuts

### Export proves presence but not semantics

Mitigation:

- assert both:
  - the sidechat response text reflects current waiting/progress semantics
  - the export contains the exact persisted transcript rows

## Testing Strategy

The implementation should lock four layers:

1. app_api supervision helper wrappers work from acceptance code
2. the new hybrid scenario produces a live waiting turn and successful sidechat
   exchange
3. debug export preserves the live sidechat session/message transcript
4. the active acceptance suite includes this scenario and stays green

## Success Criteria

This follow-up is successful when:

- the existing 2048 capstone remains green and still exports review-side
  supervision transcript artifacts
- a new hybrid acceptance scenario passes while asking sidechat questions during
  active/waiting work
- the answer is grounded in current progress/blocker semantics, not terminal
  summary semantics
- debug export preserves the live sidechat transcript
- the full `core_matrix` verification suite and full active acceptance suite,
  including the 2048 capstone, both pass
