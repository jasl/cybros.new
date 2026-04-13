# Execution Epoch Lazy Bootstrap Design

## Goal

Keep `ConversationExecutionEpoch` as the long-term execution continuity model,
but stop materializing it when a `Conversation` row is created.

Instead:

- `Conversation` creation only decides the initial
  `current_execution_runtime_id`
- `ConversationExecutionEpoch` is created on the first real execution entry
- `execution_continuity_state` distinguishes "container exists" from
  "execution continuity exists"

This design preserves room for future runtime handoff without forcing the root
conversation bootstrap path to eagerly create execution lineage state.

## Problem

Today `Conversation` eagerly creates an epoch through
`after_create :ensure_initial_execution_epoch!` in
`app/models/conversation.rb`.

That has three costs:

1. It makes `Conversation` bootstrap heavier than it needs to be.
2. It couples "container created" and "execution continuity established" into
   a single state transition.
3. It duplicates state immediately:
   `current_execution_runtime_id`, `current_execution_epoch_id`, and
   `execution_continuity_state` all become populated before any turn exists.

The business model for handoff is still unfinished. Runtime handoff is rejected
for existing conversations today, so the eager epoch is mostly preallocated
future structure rather than currently required product behavior.

## Non-Goals

This change does not:

- remove `ConversationExecutionEpoch`
- implement runtime handoff
- change `latest_*` anchor semantics
- move execution snapshot creation out of the request path
- redesign workflow graph materialization

## Options Considered

### Option 1: Keep eager epoch creation

This is the current behavior.

Pros:

- smallest code surface
- every `Conversation` is immediately execution-ready

Cons:

- keeps root bootstrap heavier than necessary
- preserves the false equivalence between "container exists" and
  "execution has started"
- forces all future optimizations to work around callback-created state

### Option 2: Lazy epoch creation, keep `execution_continuity_state = ready`

Pros:

- cheaper to land than adding a new state
- minimal API churn

Cons:

- `ready` becomes semantically ambiguous
- API payloads can report `ready` while `current_execution_epoch_id` is `nil`
- future handoff state modeling stays muddled

### Option 3: Lazy epoch creation, add `execution_continuity_state = not_started`

Recommended.

Pros:

- cleanly separates "conversation container" from "execution continuity"
- preserves `current_execution_runtime_id` as a useful pre-execution choice
- keeps `ready` meaningful: an epoch exists and execution continuity is active
- reduces the chance of future handoff code assuming an epoch always exists

Cons:

- requires enum and API contract updates
- requires test updates for bare conversation creation

## Recommended Design

### 1. `Conversation` remains the container and runtime chooser

`Conversation` creation should still pick a `current_execution_runtime` using
the existing priority:

- explicit override
- parent conversation runtime
- workspace default runtime
- agent default runtime

That logic already exists in
`Conversation#default_current_execution_runtime`.

What changes is the meaning of creation:

- container exists
- owner/workspace/agent are fixed
- runtime choice is known
- execution continuity has not started yet

### 2. `ConversationExecutionEpoch` becomes first-execution state

The epoch is no longer created from `Conversation.after_create`.

It is created only when some service needs an execution identity for a turn or
process boundary. The canonical entry point remains
`ConversationExecutionEpochs::InitializeCurrent`.

This keeps the epoch model and all downstream foreign keys intact while
removing it from the root conversation bootstrap path.

### 3. `execution_continuity_state` becomes explicit

`Conversation.execution_continuity_state` should become:

- `not_started`
- `ready`
- `handoff_pending`
- `handoff_blocked`

Semantics:

- `not_started`: no current epoch exists yet
- `ready`: current epoch exists and matches `current_execution_runtime_id`
- `handoff_pending`: reserved for future handoff work
- `handoff_blocked`: reserved for future handoff work

`ready` should no longer mean "the conversation is eligible to be started."
It should mean "execution continuity has been established."

### 4. `current_execution_runtime_id` stays on `Conversation`

This field is still useful before the first turn:

- list/detail surfaces can show the runtime the conversation is configured to
  use
- first-turn runtime overrides still have a place to land
- future handoff can still compare current runtime choice to execution history

The duplicated state concern is not that this column exists. The issue is that
it is currently forced to synchronize with an eagerly created epoch even when
no execution has begun.

### 5. `FreezeExecutionIdentity` should initialize with the final runtime

The current implementation initializes the current epoch before fully resolving
the requested runtime override path.

That creates an avoidable double-write on the first turn:

- initialize epoch from default runtime
- retarget epoch to override runtime

The write path should become:

1. Resolve the requested runtime for this entry.
2. If there is no current epoch, initialize it with that resolved runtime.
3. If a current epoch exists and the request wants a different runtime,
   preserve current behavior for the supported branch and reject unsupported
   handoff.
4. Return an `ExecutionIdentity` whose `execution_epoch` and
   `execution_runtime` already agree.

That keeps first-turn runtime override behavior correct while removing the
bootstrap-retarget churn.

Under the same destructive-refactor rule, `ConversationExecutionEpochs::RetargetCurrent`
should become a true retarget-only service. It should no longer create the
current epoch as a side effect when one is missing. Continuity bootstrap should
have exactly one creation entry point: `ConversationExecutionEpochs::InitializeCurrent`.

## Write Path Changes

### Conversation creation

`Conversations::CreateRoot` and child conversation builders continue to:

- create the `Conversation`
- set `current_execution_runtime`
- leave `current_execution_epoch_id` as `nil`
- set `execution_continuity_state = "not_started"`

They no longer create an initial epoch.

### First turn entry

All turn entry services already flow through `Turns::FreezeExecutionIdentity`
and explicitly pass `execution_identity.execution_epoch` into `Turn.create!`.

That means user turns, automation turns, queued follow-ups, agent turns,
subagent delivery turns, and imported transcript rehydration can all inherit
the new lazy bootstrap behavior without needing a separate epoch-creation
branch in each service.

Under the destructive-refactor rules for this optimization round, direct model
construction should also become stricter. `Turn` should stop implicitly
copying `conversation.current_execution_epoch` in a
`before_validation :default_execution_epoch` fallback.

After this change, any direct `Turn.create!` path that bypasses
`Turns::FreezeExecutionIdentity` must either:

- initialize the conversation epoch explicitly first, or
- pass `execution_epoch:` explicitly

That is a better long-term shape because it turns hidden continuity
assumptions into immediate failures. In the current codebase, this mostly
affects tests, fixtures, and helper builders rather than app write paths.

Two app write paths still deserve explicit verification because they enter a
fresh conversation outside the standard user-turn request flow:

- `SubagentConnections::SendMessage`, which can append the first completed turn
  to a child conversation that starts in `not_started`
- `ConversationBundleImports::RehydrateConversation`, which seeds imported
  completed turns into a freshly created root conversation

### Process creation

`ProcessRun` already defaults its epoch from the owning turn. That behavior
should remain unchanged. The important invariant is simply that a turn cannot
be created without a real epoch.

### Automation roots and child conversations

This lazy bootstrap contract applies to every conversation creation path, not
just interactive root conversations.

That means:

- `Conversations::CreateAutomationRoot` should also produce
  `execution_continuity_state = "not_started"`
- child conversation builders should continue to copy
  `current_execution_runtime`, but they should not materialize a current epoch
  until execution actually starts in the child

The meaning is consistent across all conversation kinds:

- runtime choice may already be known
- execution continuity does not exist until first execution entry

## Read/API Behavior

### Bare conversation creation

After a bare `Conversations::CreateRoot.call`:

- `current_execution_runtime_id` is present when a runtime can be resolved
- `current_execution_epoch_id` is `nil`
- `execution_continuity_state = "not_started"`

### Conversation-first API (`conversations#create`)

The current app-facing endpoint creates the conversation and immediately starts
the first turn in the same request.

For that path:

- the first turn still forces epoch initialization
- the final response should still usually show
  `current_execution_epoch_id` present
- `execution_continuity_state` should still end as `ready`

So this design changes the meaning of bare conversation creation more than it
changes the existing conversation-first request contract.

### Non-execution preview and configuration surfaces

Not every place that needs runtime or agent-definition context should
materialize execution continuity.

In particular, these surfaces must remain pre-execution-safe:

- `RuntimeCapabilities::PreviewForConversation`
- `Conversations::UpdateOverride`

They need the configured runtime and active agent definition so they can:

- preview the visible tool catalog
- expose the configured execution runtime in preview payloads
- validate and apply override payloads against the active override schema

But they do **not** represent the start of execution continuity. A bare
conversation that is only previewed or configured should remain:

- `current_execution_epoch_id = nil`
- `execution_continuity_state = "not_started"`

That means the implementation must separate two concepts that are currently
collapsed inside `Turns::FreezeExecutionIdentity`:

- **read-only execution context resolution**
- **execution identity freezing with epoch materialization**

The recommended shape is to introduce a read-only resolver that returns:

- `agent_definition_version`
- `execution_runtime`
- `execution_runtime_version`

from the conversation's configured runtime and active agent connection, without
calling `ConversationExecutionEpochs::InitializeCurrent`.

That resolver should become the single source of truth for
agent/runtime/version lookup. `Turns::FreezeExecutionIdentity` should remain
the canonical write-path entry for real turn/process execution, but its job
should narrow to:

- choosing the final runtime for this entry
- materializing continuity if needed
- attaching the extra write-path-only state such as `agent_config_state`

Read-only preview/configuration flows should stop using
`Turns::FreezeExecutionIdentity`, and write-path identity freezing should stop
duplicating the same context-resolution logic.

## Schema and Migration Strategy

Because `core_matrix` is still pre-launch and this codebase is already using
destructive schema rewrites during the current optimization round, this change
should follow the same workflow instead of adding a forward-only migration.

Recommended schema behavior:

- update the original conversations migration so
  `conversations.execution_continuity_state` defaults to `not_started`
- regenerate `db/schema.rb` from a clean database using the project-standard
  reset flow
- preserve the runtime/epoch nullable shape exactly as today; only the default
  and bootstrap semantics change

`current_execution_epoch_id` already allows `NULL`, so no nullability change is
required.

Recommended rebuild flow from `/Users/jasl/Workspaces/Ruby/cybros/core_matrix`:

```bash
rails db:drop && rm db/schema.rb && rails db:create && rails db:migrate && rails db:reset
```

## Risks

### Hidden assumptions that every conversation has an epoch

Tests and presenters currently assert this in a few places. The main risk is
not data corruption, but stale assumptions in service and request tests.

Mitigation:

- update service tests for `CreateRoot`
- update service tests for `CreateAutomationRoot` and child conversation
  builders
- keep first-turn request tests asserting `ready`
- add a targeted `FreezeExecutionIdentity` test for first-turn override order

### Hidden call sites that materialize an epoch outside real execution entry

The most important semantic risk is not direct `Turn.create!`; it is
read-oriented or configuration-oriented code that currently reaches
`Turns::FreezeExecutionIdentity` just to inspect runtime context.

Today that includes:

- `RuntimeCapabilities::PreviewForConversation`
- `Conversations::UpdateOverride`

If those call sites keep using the write-path materializer, a bare
conversation can silently transition from `not_started` to `ready` just by
opening a preview or saving overrides.

Mitigation:

- introduce a read-only execution-context resolver
- move preview/override schema lookup off `Turns::FreezeExecutionIdentity`
- add tests that preview and override updates do not create an epoch on a bare
  conversation

### Hidden first-entry write paths outside the main turn services

Not every first execution entry comes from `StartUserTurn`,
`StartAutomationTurn`, `StartAgentTurn`, or `QueueFollowUp`.

Today there are also write paths that create the first turn for a fresh
conversation through other services:

- `SubagentConnections::SendMessage`
- `ConversationBundleImports::RehydrateConversation`

If those paths are not covered, lazy bootstrap can still regress by:

- failing to initialize the epoch on first write
- leaving the conversation in `not_started` after a completed turn exists
- quietly shifting SQL cost without re-baselining the affected tests

Mitigation:

- add targeted regression coverage for subagent delivery and import rehydrate
- re-baseline the explicit SQL budget in `subagent_connections/send_message`
- assert imported conversations end in `ready` once rehydration creates turns

### Direct model construction and test fixtures bypass lazy bootstrap

Several tests and helper paths create `Turn` rows directly instead of going
through `Turns::FreezeExecutionIdentity`.

After this change, those paths will fail unless they either initialize the
conversation epoch first or pass `execution_epoch:` explicitly.

Mitigation:

- audit direct `Turn.create!` and `Turn.new` test paths
- add a small helper or explicit setup step for tests that need a current epoch
- keep app write paths flowing through `Turns::FreezeExecutionIdentity`

### First-turn runtime override creates the wrong epoch

If `InitializeCurrent` still runs before runtime resolution, the first turn can
create an epoch on the default runtime and then retarget it.

Mitigation:

- reorder `FreezeExecutionIdentity`
- add a test that the first epoch uses the override runtime directly
- make the test fail if `ConversationExecutionEpochs::RetargetCurrent` is
  called during first-turn override bootstrap

### API payloads show ambiguous continuity state

If the new state is not wired through all code paths, clients can observe
`current_execution_epoch_id = nil` with `ready`.

Mitigation:

- treat `not_started` as the only valid state when `current_execution_epoch_id`
  is `nil` and no handoff state is active
- update presenter/request tests explicitly

### Query budgets move from conversation creation to first turn entry

Moving epoch creation out of `Conversations::CreateRoot` does not remove the
work. It mostly relocates it to the first execution entry.

That means:

- bare conversation bootstrap should get cheaper
- first-turn entry services may get slightly more expensive
- query budget tests need re-baselining rather than blind preservation

Mitigation:

- explicitly rerun the SQL budget tests for first-turn entry surfaces
- document the before/after counts for `CreateRoot` and the conversation-first
  request path separately

Observed post-implementation probe counts on 2026-04-13:

- `Conversations::CreateRoot`: `16` SQL queries
- `Conversations::CreateAutomationRoot`: `16` SQL queries
- `Workbench::CreateConversationFromAgent`: `97` SQL queries
- `Turns::StartUserTurn`: `26` SQL queries
- `SubagentConnections::SendMessage`: `30` SQL queries

Comparison to the pre-change analysis snapshot:

- `CreateRoot` dropped from the earlier service-phase estimate of roughly `20`
  queries to `16`
- `Workbench::CreateConversationFromAgent` dropped from the earlier direct
  probe of `143` queries to `97`
- first-entry turn paths moved upward as expected because epoch bootstrap now
  happens there instead of during bare conversation creation

### Behavior docs drift from the new continuity semantics

Current behavior docs still describe eager continuity bootstrap and the old
first-turn override retarget story.

Mitigation:

- update `docs/behavior/turn-entry-and-selector-state.md`
- update `docs/behavior/conversation-structure-and-lineage.md`
- do not treat the implementation as complete until those behavior docs match
  the landed code

## Verification Plan

The change is successful when:

- `Conversations::CreateRoot.call` leaves the conversation without a current
  epoch and with `execution_continuity_state = "not_started"`
- `Conversations::CreateAutomationRoot.call` does the same
- child conversation builders preserve `current_execution_runtime` without
  creating a current epoch
- `ConversationExecutionEpochs::InitializeCurrent.call` transitions the
  conversation to `ready`
- `RuntimeCapabilities::PreviewForConversation.call` does not create an epoch
  for a bare conversation
- `Conversations::UpdateOverride.call` does not create an epoch for a bare
  conversation
- first-turn runtime overrides initialize the epoch directly on the requested
  runtime
- `AppAPI conversations#create` still returns a conversation whose continuity
  state is `ready`
- `Turn` no longer has an implicit `default_execution_epoch` fallback
- direct `Turn.create!` test fixtures are updated so they either initialize the
  conversation epoch first or pass `execution_epoch:` explicitly
- `SubagentConnections::SendMessage.call` bootstraps continuity on the first
  child-conversation delivery and its SQL budget is re-measured
- `ConversationBundleImports::RehydrateConversation.call` bootstraps
  continuity on the first imported turn and leaves the imported conversation in
  `ready`
- query count for `Conversations::CreateRoot` drops relative to the eager
  callback version
- the query budget surfaces for first-turn entry are re-measured and updated to
  reflect the new work distribution
- behavior docs describe `not_started` bare conversations and the new
  read-only-versus-materializing boundary consistently

## Recommendation

Land this as an isolated cleanup before any broader workflow or snapshot
refactor.

It gives the schema a cleaner semantic boundary:

- `Conversation` creation means "working container exists"
- epoch creation means "execution continuity has begun"

That separation is worth preserving even if larger performance work happens
later.

## Pattern Reuse And Destructive-Refactor Follow-Ons

This lazy-bootstrap pattern is worth reusing, but not blindly.

The rule is:

- keep boundary truth eager
- make derived execution state lazy
- if a one-to-one derived row has no independent lifecycle, prefer collapsing
  it into the owning boundary instead of merely materializing it later

### Good fit for the same pattern

The best nearby follow-on candidate is `ConversationCapabilityPolicy`, but only
under a stronger destructive-refactor mindset than this document's narrow
scope.

Why it is different from `ConversationExecutionEpoch`:

- `ConversationExecutionEpoch` has a real independent lifecycle
- turns and processes hold durable foreign keys to it
- future runtime handoff needs an explicit continuity object

By contrast, `ConversationCapabilityPolicy` today is:

- a one-to-one row
- created eagerly with every root conversation
- derived from workspace policy projection
- primarily read by supervision/control gates

That means the long-term best shape is probably **not** "lazy-create the same
table later". The better destructive-refactor option is to remove the eager
projection row from the hot path entirely by either:

1. collapsing the effective capability fields into `Conversation` or
   `ConversationDetail`, or
2. resolving them directly from workspace-backed policy state until a durable
   supervision artifact explicitly snapshots them

If this follow-on is taken, snapshot artifacts should store the actual
effective flags they need, rather than depending on a separate
`conversation_capability_policy_public_id` row identity.

### Possible fit, but lower priority

The second candidate is root-conversation `LineageStore` bootstrap.

Today every root conversation eagerly creates:

- `LineageStore`
- `LineageStoreSnapshot`
- `LineageStoreReference`

This may be over-eager for conversations that never branch, import provenance,
or write lineage-backed variables.

However, lineage is more structural than capability policy:

- branch/fork/checkpoint flows depend on it
- purge and blocker logic depend on live lineage references
- behavior docs currently treat root-lineage presence as part of the model

So this should only be revisited after the execution-epoch change lands and
only if the product is willing to explicitly model a `lineage_not_initialized`
state.

### Poor fit for this pattern

`AgentTaskRun` tool-binding freeze is **not** a strong next candidate even
though it creates eager rows.

Those bindings are deeply coupled to:

- tool invocation lifecycle
- command runs
- MCP/tool execution governance
- agent control/report reconciliation

That makes them execution substrate, not cheap preallocated projection state.
It may still be worth optimizing later, but not with the same lazy-bootstrap
pattern used here.
