# Conversation Bootstrap Slimming Design

## Goal

Slim down `Conversation` bootstrap and the related child-conversation bootstrap
paths by removing conversation-local projection rows that do not need to exist
as standalone resources and by delaying lineage substrate creation until it is
actually needed.

This design assumes:

- destructive refactors are allowed on the current branch
- compatibility with the current unfinished schema is not required
- original migrations may be rewritten in place
- local and test databases may be rebuilt from scratch

The target is not “smaller SQL at any cost.” The target is a cleaner long-term
model where:

- `Conversation` stores its own hot authority state directly
- lineage substrate is created only when variable provenance actually exists
- root and child conversation creation stop preallocating rows whose absence is
  already representable in the domain

## Scope

This pass focuses on two concrete refactors under the `Conversation` domain:

1. Collapse `ConversationCapabilityPolicy` into `Conversation`
2. Make `LineageStore` bootstrap lazy and conversation-owned instead of
   root-conversation-preallocated

## Non-Goals

This pass does not:

- redesign `ConversationCapabilityGrant`
- move workflow graph creation out of request paths yet
- change transcript lineage semantics
- change conversation branching, fork, or checkpoint product rules
- redesign `ConversationSupervisionState`
- redesign `ConversationExecutionEpoch`

Those remain follow-on work.

## Current Baseline

The current code already shows exactly where conversation bootstrap weight
comes from.

### Observed root bootstrap cost

Using `rails runner -e test` with the existing `test/test_helper` factory
helpers, a fresh `Conversations::CreateRoot.call(workspace: ...)` currently
costs:

- `16` SQL statements
- `+1` `conversations` row
- `+1` `conversation_closures` row
- `+1` `conversation_capability_policies` row
- `+1` `lineage_stores` row
- `+1` `lineage_store_snapshots` row
- `+1` `lineage_store_references` row

### Measured local costs inside root bootstrap

These were also measured in isolation:

- `create_self_closure!`
  - `2` SQL
  - `+1` `conversation_closures` row
- `LineageStores::BootstrapForConversation.call`
  - `5` SQL
  - `+1` `lineage_stores` row
  - `+1` `lineage_store_snapshots` row
  - `+1` `lineage_store_references` row
- `create_capability_policy_for!`
  - `3` SQL
  - `+1` `conversation_capability_policies` row

### Measured child lineage attach cost

For child conversation initialization, the current lineage attachment step
alone costs:

- `4` SQL
- `+1` `lineage_store_references` row

The combined current child initialization step
(`create_parent_closures! + create_lineage_store_reference_for!`) costs:

- `10` SQL
- `+2` `conversation_closures` rows
- `+1` `lineage_store_references` row

These numbers are the baseline every proposal in this document is measured
against.

## Problem 1: `ConversationCapabilityPolicy` Is Not A Real Boundary Resource

`ConversationCapabilityPolicy` is currently created on every root conversation
bootstrap by `Conversations::CreationSupport#create_capability_policy_for!`.

The row is a projection from `WorkspacePolicies::Capabilities` and currently
stores:

- `supervision_enabled`
- `detailed_progress_enabled`
- `side_chat_enabled`
- `control_enabled`
- `policy_payload`

The problems are structural:

1. It is conversation-owned durable state, but it is stored in an extra table
   even though the hot read path only needs four booleans.
2. It is created synchronously for every root conversation even when no
   supervision session is ever opened.
3. The main readers (`ConversationSupervisionAccess`,
   `EmbeddedAgents::ConversationSupervision::BuildSnapshot`,
   `Conversations::UpdateSupervisionState`) treat it as a one-to-one
   projection, not as an independently evolving aggregate.
4. `Conversation` already owns another conversation-scoped policy surface
   directly on its own row:
   - `enabled_feature_ids`
   - `during_generation_input_policy`

This means the current split is inconsistent. One conversation-scoped policy
is row-local, the other is stored as a side table.

## Recommended Direction For Capability Authority

### Remove the `ConversationCapabilityPolicy` table

Do not replace it with lazy materialization of the same table. That would keep
the wrong shape alive.

The long-term better model is:

- `Conversation` directly stores the hot authority booleans:
  - `supervision_enabled`
  - `detailed_progress_enabled`
  - `side_chat_enabled`
  - `control_enabled`
- `Conversation` becomes the single durable source of conversation-level
  supervision authority
- supervision snapshots and sessions keep frozen authority snapshots in their
  own payloads, as they already do

### Do not preserve a durable conversation capability payload row

The current `policy_payload` is not used as a hot boundary field. It mainly
captures:

- available capabilities
- disabled capabilities
- effective capabilities

That information is useful for workspace policy presentation and for snapshot
debugging, but it does not justify a permanent one-to-one policy table on
every conversation.

The recommended model is:

- keep workspace capability presentation on the workspace side
- freeze the four effective booleans onto the conversation at creation time
- snapshot the resolved authority into supervision artifacts when needed
- stop carrying a durable `ConversationCapabilityPolicy` row or public id

### Replace policy objects with authority snapshots

A few services currently expose a `policy` object because the row exists:

- `AppSurface::Policies::ConversationSupervisionAccess`
- `EmbeddedAgents::ConversationSupervision::Authority`
- `ConversationControl::AuthorizeRequest`

After this refactor, those APIs should stop surfacing a
`ConversationCapabilityPolicy` record and instead expose a plain authority
snapshot hash or lightweight value object.

Under the destructive-refactor rule, renaming `policy` to
`capability_snapshot` or `authority_snapshot` is preferable to preserving a
misleading name tied to a deleted table.

### Preserve the current product contract

This refactor does **not** change the business rule:

- workspace policy changes affect future conversations
- existing conversations keep the authority state that was projected when the
  conversation was created

The storage shape changes, not the rule.

## Problem 2: Root `LineageStore` Bootstrap Is Preallocating Structure

`Conversations::CreateRoot` currently does this unconditionally:

1. create the `Conversation`
2. create the self closure
3. create a `LineageStore`
4. create a root `LineageStoreSnapshot`
5. create a `LineageStoreReference`

That means a bare conversation with no conversation-local variable history
still gets a lineage substrate.

The current behavior docs also assume:

- every root conversation owns one lineage store
- every child conversation always gets a reference at creation

That is a clean model if lineage state always exists. It is not a clean model
if empty lineage is already expressible as “no reference.”

## Recommended Direction For Lineage Bootstrap

### Stop preallocating lineage state at root creation

A bare root conversation should start with:

- no `LineageStore`
- no `LineageStoreReference`
- no lineage snapshots

Conversation creation should only establish:

- the conversation container
- ownership and current execution anchors
- closure structure

Lineage substrate should appear only when there is actual lineage state or a
real need to inherit lineage state.

### Make lineage ownership conversation-owned, not root-kind-owned

If destructive refactoring is allowed, the cleaner long-term model is not just
“lazy root bootstrap.” It is:

- rename `LineageStore.root_conversation_id` to `owner_conversation_id`
- rename `Conversation#root_lineage_store` to `owned_lineage_store`
- rename `root_lineage_store_blocker` to `owned_lineage_store_blocker`

This matters because once bootstrap is lazy, a non-root child conversation may
be the first place where lineage state is created.

Example:

- root conversation starts with no lineage reference
- fork happens before any lineage write
- child conversation also starts with no lineage reference
- child later performs the first conversation-local variable write

If the schema still says “only root conversations own stores,” the model
becomes awkward and pushes the system toward hidden parent bootstrap.

If the schema says “the conversation that first materializes this lineage
store owns it,” the model stays clean:

- root conversations may own stores
- child conversations may also own stores
- inherited references still work the same when a parent already has lineage
  state

### Child creation should copy lineage only when lineage exists

Current child bootstrap always creates a `LineageStoreReference`.

The recommended rule is:

- if the parent has a live `lineage_store_reference`, child creation copies a
  reference to the same current snapshot
- if the parent has no `lineage_store_reference`, child creation does not
  create one

This means empty lineage does not allocate rows.

### Query support must tolerate missing references

Today `LineageStores::QuerySupport` assumes a reference exists. After this
refactor:

- `GetQuery` returns `nil` when no reference exists
- `ListKeysQuery` returns an empty page when no reference exists
- `MultiGetQuery` returns an empty hash when no reference exists
- `ConversationVariables::VisibleValuesResolver` continues to work without
  forcing bootstrap

“No conversation-local lineage state yet” becomes a first-class readable
state.

### Write support becomes the bootstrap boundary

For write operations such as:

- `LineageStores::Set`
- `LineageStores::DeleteKey`
- `LineageStores::CompactSnapshot`

the write support layer becomes responsible for ensuring a reference exists.

The rule becomes:

- if the conversation already has a reference, write through it
- if not, create:
  - a `LineageStore` owned by this conversation
  - a root snapshot
  - a reference
  and then continue the write

This makes lineage bootstrap explicit, local, and naturally idempotent.

### Deletion and purge semantics generalize cleanly

`FinalizeDeletion` already removes the live `lineage_store_reference` if it
exists.

Under the new model:

- final deletion still removes the live reference first
- purge is blocked while an owned lineage store still exists
- lineage garbage collection reconciles deleted conversations by
  `owner_conversation_id`

The semantics become broader, not weaker:

- any conversation that owns a lineage store must wait for that store to be
  garbage-collected before final purge

## Why This Is Better Than A Simpler Lazy Strategy

Two weaker alternatives were considered and rejected.

### Option A: Keep `ConversationCapabilityPolicy`, just create it lazily

Rejected because:

- it keeps a hot one-to-one authority projection off the conversation row
- it preserves misleading service APIs that expose policy rows
- it still treats a projection table as a first-class durable aggregate

### Option B: Lazy root lineage bootstrap, but keep `root_conversation_id`

Rejected because:

- once child conversations can remain reference-free, first lineage ownership
  no longer reliably belongs to `kind = root`
- it encourages hidden parent bootstrap to preserve a naming assumption
- it keeps blocker and ownership terminology tied to an eager design that this
  refactor is explicitly replacing

## Recommended End State

After this refactor:

- `Conversation` directly owns supervision/control authority booleans
- `ConversationCapabilityPolicy` is gone
- supervision artifacts keep authority snapshots, not policy-row references
- bare root conversations create no lineage substrate
- child conversations inherit lineage references only when the parent already
  has lineage state
- lineage query surfaces treat “no reference” as empty state, not as an error
- lineage write surfaces are the only place that materialize lineage substrate
- lineage ownership and blocker naming use conversation-owned semantics rather
  than root-kind semantics

## Measured Weight-Reduction Targets

These are the explicit targets this plan should prove with tests.

### After capability-policy collapse

`Conversations::CreateRoot` should:

- drop the extra `conversation_capability_policies` row entirely
- reduce from `16` SQL to `<= 13` SQL

### After lazy lineage bootstrap

Bare `Conversations::CreateRoot` should:

- create no `lineage_stores`
- create no `lineage_store_snapshots`
- create no `lineage_store_references`
- reduce from the post-policy-collapse baseline to `<= 8` SQL

### For child creation when parent has no lineage state

`CreateFork`, `CreateBranch`, and `CreateCheckpoint` should:

- create no lineage reference row for the child
- save at least the currently measured `4` SQL / `+1` reference attach cost

### For first conversation-local lineage write on an empty conversation

`LineageStores::Set` should:

- bootstrap the lineage substrate exactly once
- create:
  - `+1` store
  - `+1` root snapshot
  - `+1` reference
  - `+1` write snapshot
  - `+1` entry
  - `+1` value when the payload is novel
- remain idempotent on repeated writes of the same value

## Behavior Docs That Must Change

This refactor must update at least:

- `docs/behavior/conversation-structure-and-lineage.md`
- `docs/behavior/conversation-supervision-and-control.md`
- `docs/behavior/canonical-variable-history-and-promotion.md`
- `docs/behavior/agent-runtime-resource-apis.md`
- any blocker-related behavior doc that still mentions
  `root_lineage_store_blocker`

## Follow-On Work

This pass should make the next deeper `Conversation` optimization easier:

- thinning API entry paths so they only write boundary truth synchronously
- moving workflow graph bootstrap and similar secondary substrate creation to
  durable async bootstrap jobs

That next step is separate. This pass is about removing the currently
unnecessary synchronous rows that are already safe to eliminate or delay.
