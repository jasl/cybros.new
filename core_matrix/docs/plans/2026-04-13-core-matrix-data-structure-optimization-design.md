# Core Matrix Data Structure Optimization Design

## Goal

Redesign the Core Matrix base schema around `Workspace` and `Conversation` as
the two app-facing center models so the system can:

- keep hot product read paths predictable and low-query
- move access control to SQL boundary lookups instead of Ruby-side rechecks
- carry owner and execution context directly on boundary and runtime tables
- treat selected denormalized columns as first-class structural truth
- preserve current business rules while replacing the underlying data shape

This design is intentionally destructive. It assumes:

- the product is still pre-launch
- compatibility with current unfinished schema is not a goal
- existing migrations may be rewritten in place
- local and test databases may be reset

This is a schema and data-structure revision. It is not a business-logic
rewrite.

## Why This Exists

The current codebase already has a useful split between:

- app-facing API controllers
- app-surface queries and presenters
- service objects
- domain models

The performance problem is not just isolated `N+1` issues. The larger issue is
that app-facing boundaries often need to reconstruct ownership and current
state by walking long chains such as:

- `workspace -> user_agent_binding -> agent`
- `conversation -> workspace -> user_agent_binding -> agent`
- `conversation -> turns -> active/latest turn`

That leads to repeat lookups, Ruby-side filtering, and hot-path policy checks
that reload records to confirm visibility. As the API surface grows, that
shape will keep generating new query inflation points even if individual
queries are tuned.

The long-term fix is to make boundary resources self-describing:

- a `Workspace` should directly answer who owns it and which agent it belongs
  to
- a `Conversation` should directly answer who owns it, which workspace and
  agent it belongs to, and what its current execution anchors are
- runtime and supervision tables should carry enough owner and execution
  context to support one-hop filtering and projection reads

## Non-Goals

This revision does not attempt to:

- change current visibility semantics for public/private resources
- change current lifecycle semantics such as retained/pending-delete/deleted
- introduce global message search or user-wide message listing
- expand the product into full projection-first read models everywhere
- redesign supervision wording or product-facing copy
- redesign usage accounting semantics

## Design Principles

### 1. `Workspace` and `Conversation` are center models

`Workspace` is the user's working context under one `Agent`.

`Conversation` is the main app-facing boundary and the durable current-state
anchor for active work.

The schema should optimize for these two resources being directly readable and
directly enforceable.

### 2. Boundary resources must be self-describing

Any app-facing resource should answer its primary access and ownership
questions from its own row or at most one obvious parent, not by reconstructing
state across several joins.

### 3. Access rules belong in SQL lookup boundaries

App-facing access should be enforced by boundary scopes such as
`accessible_to_user(user)` and owner-scoped relations. The system should stop
loading records and then re-authorizing them in Ruby through reload-heavy
predicate objects.

### 4. Denormalized columns are structural truth

Selected owner and current-state columns are not treated as opportunistic
caches. They are part of the canonical schema and must be maintained
transactionally.

### 5. Explicit services own synchronization

Center denormalized columns must be maintained by explicit write services
inside well-defined transactions. They should not be maintained by model
callbacks.

### 6. Database constraints should carry more of the consistency load

Where the design intentionally duplicates owner or context columns, the schema
should enforce alignment through foreign keys, unique constraints, and
relational invariants. Ruby validations remain useful, but they should not be
the primary protection.

### 7. Optimize the base schema before introducing more projections

Specialized read models remain appropriate for supervision feeds and similar
high-churn surfaces, but the first step is to fix the base relational shape so
new app surfaces do not inherit join-heavy access patterns.

## Strategic Direction

Three broad options were considered:

1. Query-shaping only
2. Boundary-resource denormalization
3. Projection-first expansion

The recommended direction is:

- use boundary-resource denormalization as the primary strategy
- apply query-shaping as hygiene during implementation
- keep projection-first expansion limited to naturally projected surfaces such
  as supervision state and feeds

The reason is simple: the current pressure comes from access-boundary
information being too far from the boundary itself. Local preload and query
cleanup help, but they do not fix the base shape.

## Target Domain Shape

The long-term schema should be organized into three categories.

### 1. Center resources

- `Agent`
- `ExecutionRuntime`
- `Workspace`
- `Conversation`
- `Turn`

These are the primary app-facing or execution-facing durable resources.

### 2. Internal coordination resources

- `UserAgentBinding`
- connection and version tables
- capability, policy, grant, and close-operation tables

These may remain important, but they are not allowed to define the ownership
shape of the app-facing resource graph.

### 3. Recomputable or projection-oriented resources

- `ConversationSupervisionState`
- `ConversationSupervisionFeedEntry`
- other read-side projections and diagnostic summaries

These should be optimized for queryability, not for perfect normalization.

## Target Model Responsibilities

### `UserAgentBinding`

`UserAgentBinding` should be demoted to an internal preference aggregate.

It should keep:

- user + agent preference state
- optional enablement or recent-use metadata

It should stop carrying:

- workspace ownership structure
- default workspace uniqueness structure
- hot-path app-surface ownership reconstruction

The resource graph should no longer require the system to hop through
`UserAgentBinding` to explain why a workspace or conversation belongs to a
user and agent pair.

### `Workspace`

`Workspace` should become the durable working-context root under one agent.

Its row should directly carry:

- `installation_id`
- `user_id`
- `agent_id`
- `default_execution_runtime_id`
- `privacy`
- `is_default`
- `name`

The key structural change is that `Workspace` should directly own the
user-agent relationship instead of deriving it through
`user_agent_binding_id`.

That lets the system answer, from one table:

- which user owns the workspace
- which agent the workspace belongs to
- whether it is the default workspace
- what the default runtime preference is

### `Conversation`

`Conversation` should become the main app-facing boundary and current-state
anchor.

Its row should directly carry:

- `installation_id`
- `user_id`
- `workspace_id`
- `agent_id`
- `current_execution_runtime_id`
- `current_execution_epoch_id`
- `active_turn_id`
- `latest_turn_id`
- `active_workflow_run_id`
- `latest_message_id`
- `last_activity_at`

This allows conversation-level app surfaces to answer:

- who owns the conversation
- which workspace and agent it belongs to
- what its current runtime is
- which turn is current
- which workflow run is current
- which message is the latest visible anchor

without reconstructing that state through subordinate tables.

### `Turn`

`Turn` should become a full-context execution unit rather than a child row
that only becomes understandable through its conversation.

Its row should directly carry:

- `installation_id`
- `user_id`
- `workspace_id`
- `agent_id`
- `conversation_id`
- `execution_runtime_id`
- `execution_epoch_id`

This gives downstream runtime and diagnostic tables a stable, compact source
for owner and execution context.

### `Agent`

`Agent` should keep its identity and visibility concerns, but it should stop
deriving hot-path launchability through connection fallback logic.

Add:

- `current_agent_definition_version_id`

The system may still keep `published_agent_definition_version_id` if it has a
distinct semantic role, but app-facing launchability should be driven by the
current active version pointer plus lifecycle and visibility.

### `ExecutionRuntime`

`ExecutionRuntime` should mirror the same structure.

Add:

- `current_execution_runtime_version_id`

The hot path should not need to infer the current active runtime version by
walking connection fallback state.

## Access Boundary Redesign

The current pattern of:

1. lookup by `public_id`
2. load the record
3. call a Ruby policy object
4. reload associated records to confirm access

should be removed from app-facing hot paths.

The replacement rule is:

access should be enforced inside the lookup relation itself.

Examples:

- `Agent.accessible_to_user(user).find_by!(public_id: ...)`
- `ExecutionRuntime.accessible_to_user(user).find_by!(public_id: ...)`
- `Workspace.accessible_to_user(user).find_by!(public_id: ...)`
- `Conversation.accessible_to_user(user).find_by!(public_id: ..., deletion_state: "retained")`

That means:

- controllers stop loading and then authorizing
- list queries stop doing `.to_a.select { ... }`
- access policy helpers stop reloading records in hot paths

### Boundary-specific access rules

Access remains semantically the same, but its data source changes.

#### `Agent`

Access depends on:

- `installation_id`
- `lifecycle_state = active`
- `visibility = public`
- or `visibility = private AND owner_user_id = current_user.id`
- optional launchability narrowing through `current_agent_definition_version_id`

#### `ExecutionRuntime`

Access depends on:

- `installation_id`
- `lifecycle_state = active`
- `visibility = public`
- or `visibility = private AND owner_user_id = current_user.id`
- optional launchability narrowing through
  `current_execution_runtime_version_id`

#### `Workspace`

Access depends on:

- `installation_id`
- `user_id = current_user.id`

At this phase, workspace access should not be reconstructed through agent
visibility.

#### `Conversation`

Access depends on:

- `installation_id`
- `user_id = current_user.id`
- `deletion_state = retained`

Again, this preserves the current owner-bound conversation semantics while
removing the join-heavy enforcement path.

## Schema Changes

### Must-change tables

#### `agents`

Add:

- `current_agent_definition_version_id`

Recommended indexes:

- `(installation_id, lifecycle_state, visibility, owner_user_id)`
- `(installation_id, current_agent_definition_version_id)`

#### `execution_runtimes`

Add:

- `current_execution_runtime_version_id`

Recommended indexes:

- `(installation_id, lifecycle_state, visibility, owner_user_id)`
- `(installation_id, current_execution_runtime_version_id)`

#### `workspaces`

Add or elevate:

- `agent_id`

Keep:

- `installation_id`
- `user_id`
- `default_execution_runtime_id`
- `privacy`
- `is_default`
- `name`

Remove:

- `user_agent_binding_id`

Recommended uniqueness:

- one default workspace per `installation_id + user_id + agent_id`

Recommended indexes:

- `(installation_id, user_id, agent_id, is_default)`
- `(installation_id, user_id, agent_id, name, id)`
- `(installation_id, user_id, is_default, updated_at)`

#### `conversations`

Add:

- `user_id`
- `active_turn_id`
- `latest_turn_id`
- `active_workflow_run_id`
- `latest_message_id`
- `last_activity_at`

Keep:

- `workspace_id`
- `agent_id`
- `current_execution_runtime_id`
- `current_execution_epoch_id`

Recommended indexes:

- `(installation_id, user_id, deletion_state, lifecycle_state, last_activity_at)`
- `(installation_id, workspace_id, deletion_state, last_activity_at)`
- `(installation_id, agent_id, user_id, deletion_state, created_at)`

#### `turns`

Add:

- `user_id`
- `workspace_id`
- `agent_id`

Keep:

- `conversation_id`
- `execution_runtime_id`
- `execution_epoch_id`

Recommended indexes:

- `(conversation_id, sequence)`
- `(installation_id, user_id, created_at)`
- `(installation_id, workspace_id, lifecycle_state, created_at)`

#### `workflow_runs`

Add:

- `user_id`
- `workspace_id`
- `agent_id`
- recommended: `execution_runtime_id`

#### `human_interaction_requests`

Add:

- `user_id`
- `workspace_id`
- `agent_id`

Recommended indexes:

- `(installation_id, user_id, lifecycle_state, created_at)`
- `(installation_id, workspace_id, lifecycle_state, created_at)`

#### `agent_task_runs`

Add:

- `user_id`
- `workspace_id`
- recommended: `execution_runtime_id`

#### `conversation_supervision_states`

Add:

- `user_id`
- `workspace_id`
- `agent_id`
- optional: `active_turn_id`

#### `conversation_supervision_feed_entries`

Add:

- `user_id`
- `workspace_id`
- `agent_id`

Recommended indexes:

- `(installation_id, user_id, occurred_at)`
- `(target_conversation_id, target_turn_id, sequence)`

### Should-change tables in the same pass if feasible

#### `workflow_nodes`

Add:

- `user_id`
- `agent_id`

#### `process_runs`

Add:

- `user_id`
- `workspace_id`
- `agent_id`

#### `tool_invocations`

Add:

- `conversation_id`
- `turn_id`
- `workflow_run_id`
- `user_id`
- `workspace_id`
- `agent_id`

#### `command_runs`

Add:

- `conversation_id`
- `turn_id`
- `workflow_run_id`
- `user_id`
- `workspace_id`
- `agent_id`

#### `execution_profile_facts`

Add:

- `agent_id`
- recommended: `execution_runtime_id`
- optional: `workflow_run_id`

### Explicitly deferred for this pass

#### `messages`

Do not add full owner/context duplication in this pass.

The system currently has no requirement to query all messages owned by one
user across all conversations, and message volume will grow faster than the
owner-bound boundary tables. The first optimization pass should therefore keep
`messages` keyed primarily by:

- `conversation_id`
- `turn_id`

#### `usage_events` and `usage_rollups`

These tables already carry several useful dimensions. They are not part of the
main structural bottleneck and should not be the center of this schema pass
unless runtime-level usage analysis becomes an immediate product need.

## Wide-Row and Hot-Path Split Policy

Owner/context denormalization is only half of the structural fix. The other
half is preventing center and runtime tables from becoming wide hot rows that
carry large JSON or text payloads into list and dashboard reads.

The relevant rule is:

split rows when they are both:

- hot in list or current-state reads
- likely to accumulate large payload columns that those reads do not need

PostgreSQL TOAST helps with storage for large values, but it does not remove
the cost of wide-row access patterns, high-churn updates, weaker HOT update
behavior, or Rails relations that still default to selecting the whole row.

### Split-now tables

#### `agent_task_runs`

This table is both hot and payload-heavy.

Keep on the header row:

- owner/context ids
- lifecycle and supervision state
- lightweight summary fields
- timestamps
- logical work and attempt fields

Move into a one-to-one detail record:

- `task_payload`
- `progress_payload`
- `supervision_payload`
- `terminal_payload`
- `close_outcome_payload`

This is the highest-value hot/cold split in the current schema.

#### `conversation_supervision_states`

This table is a likely board and dashboard read source.

Keep on the header row:

- lane/state fields
- lightweight summaries
- counts
- retry timestamps
- lightweight badge data

Move into a one-to-one detail record:

- `status_payload`

The board card path should not carry machine-oriented detail payloads by
default.

#### `human_interaction_requests`

This table is a natural inbox and review-list source.

Keep on the header row:

- owner/context ids
- type
- blocking flag
- lifecycle state
- expiration and resolution timestamps
- optional lightweight summary fields

Move into a one-to-one detail record:

- `request_payload`
- `result_payload`

The request list path should only pay for payload loading when the user opens
or processes the request.

#### `conversations`

`Conversation` is a center table and should stay narrow.

Keep on the header row:

- owner/context ids
- lifecycle and deletion state
- current-state pointers
- title and summary metadata
- activity timestamps

Move out of the center row:

- `override_payload`
- `override_reconciliation_report`

These should become either:

- a dedicated one-to-one detail table, or
- a `JsonDocument`-backed document reference

The center conversation row should remain a header and anchor row, not a
configuration payload container.

### Split-soon tables

These are not as urgent as the tables above, but they are strong candidates in
the same revision if the implementation cost remains acceptable.

#### `workflow_runs`

Keep on the header row:

- owner/context ids
- lifecycle state
- wait state
- wait reason kind
- retry timestamps
- blocking resource refs

Move out of the header row:

- `wait_reason_payload`
- detailed recovery/resume payload fields when they become heavier

`wait_last_error_summary` may remain inline if it stays compact, but the row
should not become the long-term container for arbitrarily complex waiting
payloads.

#### `process_runs`

Keep on the header row:

- owner/context ids
- kind
- lifecycle state
- timestamps
- exit status

Move out if row width becomes material:

- `metadata`
- `close_outcome_payload`

#### `turns`

This pass should first add owner/context columns and keep behavior stable. A
later pass may split execution snapshot-style columns such as:

- `feature_policy_snapshot`
- `resolved_config_snapshot`
- `resolved_model_selection_snapshot`
- `origin_payload`

if turn-header reads become sensitive to row width.

### Deferred split targets

#### `messages`

Do not split message content in this pass.

The transcript path actually needs the message body, and there is no current
product need for user-wide message listing that would justify a message-header
and message-body split yet.

#### `tool_invocations` and `command_runs`

These tables already externalize several large payloads through document
references. In this pass, they benefit more from owner/context denormalization
than from immediate hot/cold splitting.

### Recommended split shapes

#### 1. Header/detail one-to-one tables

Use this for hot rows with one current detail payload:

- `agent_task_runs`
- `conversation_supervision_states`
- `human_interaction_requests`
- possibly `workflow_runs`

The header row remains list-safe and index-friendly. Detail is loaded only for
processing or drill-down views.

#### 2. `JsonDocument` references

Use this for large, flexible, weakly queryable payloads such as:

- conversation overrides
- waiting payloads
- heavyweight execution snapshots

This keeps the center table narrow while reusing the existing document storage
direction already present in the codebase.

### Additional tests for split tables

Any header/detail split introduced in this revision should add tests for:

- transactional creation of header and detail together
- rollback safety when detail persistence fails
- header-only reads staying independent from detail payload loading
- current-state updates not accidentally mutating detached cold payloads
- list queries continuing to avoid detail joins unless explicitly requested

## Database Constraint Direction

This pass should increase the role of schema-level consistency rules.

Where denormalized owner or context columns are added, the schema should rely
more heavily on:

- foreign keys
- composite uniqueness
- relational alignment constraints

Examples of desired alignment:

- `Workspace` owner and agent alignment
- `Conversation` owner and workspace alignment
- `Turn` owner and conversation alignment
- runtime-resource alignment with `Turn` and `Conversation`

Not every table needs the heaviest possible composite constraint set
immediately, but the center chain should.

## Write-Side Synchronization Model

Denormalized columns in this design fall into two categories.

### 1. Immutable ownership and context duplication

These are copied once at creation time and then treated as durable truth:

- `workspaces.user_id`
- `workspaces.agent_id`
- `conversations.user_id`
- `conversations.workspace_id`
- `conversations.agent_id`
- `turns.user_id`
- `turns.workspace_id`
- `turns.agent_id`
- owner/context columns on runtime and supervision tables

These columns should not drift after creation.

### 2. Mutable current-state anchors

These evolve during execution:

- `conversations.active_turn_id`
- `conversations.latest_turn_id`
- `conversations.active_workflow_run_id`
- `conversations.latest_message_id`
- `conversations.last_activity_at`
- `agents.current_agent_definition_version_id`
- `execution_runtimes.current_execution_runtime_version_id`

These must be maintained by explicit write services inside transactions.

## Transaction Rules

### Default workspace creation

Creating or materializing the default workspace must happen in one
transactional path that writes:

- `installation_id`
- `user_id`
- `agent_id`
- `default_execution_runtime_id`
- `privacy`
- `is_default`
- `name`

The database unique constraint must be allowed to resolve concurrent creation
attempts safely.

### Conversation creation

The durable conversation creation boundary should commit, in one transaction:

- the conversation row with owner/context columns
- the first turn
- the first message
- the first workflow run
- the current-state pointer updates on the conversation row

Background workflow execution may remain asynchronous, but the app-facing
conversation anchors must be complete at commit time.

### Runtime progression

Turn lifecycle changes and related app-facing current-state pointer changes
should commit atomically. Center-state columns must not rely on eventual
compensation.

## Callback Policy

Center denormalized columns should not be maintained by model callbacks.

They should be owned only by explicit application services so the write graph,
transaction boundary, and failure behavior remain understandable.

Callbacks may still be used for small local normalization concerns, but not for
the primary synchronization of ownership or current-state anchors.

## Query and Service Consequences

This design implies several code-level changes, even though the goal is data
structure rather than business logic.

### The following hot-path patterns should disappear

- list queries that do `.to_a.select { policy }`
- access checks that reload records through a generic usability helper
- repeated `find_by` calls for the same binding or default workspace inside one
  request
- active/latest turn resolution by scanning turns for every feed-style read

### The following code should be simplified or retired from hot paths

- `InstallationScopedLookup`
- `AppAPI::BaseController` authorization chaining
- `ResourceVisibility::Usability` as a hot-path access mechanism
- app-surface query objects that still depend on `UserAgentBinding` for
  ownership reconstruction

`ResourceVisibility::Usability` may still remain for low-frequency assertions
or tests, but it should not remain the primary production access boundary.

## Testing Requirements

This schema pass requires stronger structural tests, but the tests exist to
protect the new structure rather than shift the project focus away from schema.

### 1. Boundary contract tests

Request and API tests should keep confirming that:

- `public_id`-based access semantics remain unchanged
- inaccessible private resources still return `not_found`
- retained/deleted visibility behavior remains unchanged

### 2. Database invariant tests

The test suite should verify schema-level rejection of misaligned data for the
center ownership chain and the key runtime-resource alignments.

### 3. Query budget tests

Add or strengthen SQL-budget tests for:

- `agents/index`
- `agents/:id/home`
- `agents/:id/workspaces`
- conversation creation
- conversation feed

The goal is not the smallest possible number. The goal is to prevent the
structure from regressing back into query-amplified patterns.

### 4. Transaction atomicity tests

Because several columns become first-class denormalized truth, the suite must
also prove atomicity for critical write paths.

Required focus areas:

- default workspace materialization
- conversation creation with first turn, first message, first workflow, and
  conversation current-state pointers
- runtime progression that updates current-state conversation anchors

Tests should prove that these writes either commit together or roll back
together, with no durable half-updated boundary state.

### 5. Concurrency tests for the highest-risk edges

At minimum:

- concurrent default workspace creation
- concurrent creation or first-turn anchor updates where pointer races are
  plausible

## Final Recommendation

The recommended implementation path is:

1. restructure the center schema around `Workspace` and `Conversation`
2. propagate owner and execution context into `Turn` and selected runtime
   tables
3. replace Ruby-side hot-path access filtering with SQL boundary lookups
4. treat denormalized columns as structural truth with explicit transactional
   ownership
5. use tests to lock down contract, invariants, query budgets, and atomicity

This keeps current business rules intact while giving Core Matrix a better base
schema for a larger app API and future UI integration.

## Scope Summary

### Must change in this revision

- center ownership and current-state columns on `Workspace`, `Conversation`,
  and `Turn`
- current-version pointers on `Agent` and `ExecutionRuntime`
- owner/context dimensions on key runtime and supervision tables
- SQL-first access boundaries
- transaction-owned synchronization rules

### Explicitly not a focus in this revision

- message-wide owner denormalization
- usage-accounting redesign
- projection-first expansion of every read surface
- product behavior changes beyond what the new structure must carry
