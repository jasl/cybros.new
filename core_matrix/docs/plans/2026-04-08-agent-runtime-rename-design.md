# Agent / Execution Runtime Rename Design

## Goal

Replace the current execution-runtime-centered terminology in Core Matrix with
a symmetric `Agent` / `ExecutionRuntime` domain model. This is an
intentional destructive change: no compatibility shims, no dual naming, and no
data preservation.

## Approved Scope

- standardize the host-side execution entity on `ExecutionRuntime`
- standardize the host-side authenticated connection on
  `ExecutionRuntimeConnection`
- rename the machine-facing API namespaces from `program_api` and
  `execution_api` to `agent_api` and `execution_runtime_api`
- rewrite baseline migrations in place instead of adding compatibility
  migrations
- regenerate the local database and `db/schema.rb` from scratch after the
  migration edits
- update tests, scripts, docs, and request payloads to the new language in the
  same change set

## Naming Decisions

### Durable Domain Entities

- `Agent` remains the durable logical agent product
- `AgentSnapshot` remains the immutable versioned agent payload
- `ExecutionRuntime` becomes the durable logical executor host/program identity
- `ExecutionRuntimeConnection` becomes the authenticated live session for an
  `ExecutionRuntime`

### New Canonical Field Names

- `default_execution_runtime` -> `default_execution_runtime`
- `execution_runtime_id` -> `execution_runtime_id`
- `execution_session_id` -> `execution_runtime_connection_id`
- `target_execution_runtime_id` -> `target_execution_runtime_id`
- `leased_to_execution_session_id` -> `leased_to_execution_runtime_connection_id`
- `runtime_fingerprint` -> `execution_runtime_fingerprint`
- `runtime_kind` -> `execution_runtime_kind`
- `runtime_connection_metadata` -> `execution_runtime_connection_metadata`
- `execution_capability_payload` -> `execution_runtime_capability_payload`
- `execution_tool_catalog` -> `execution_runtime_tool_catalog`

### HTTP / Protocol Naming

- `/program_api/*` -> `/agent_api/*`
- `/execution_api/*` -> `/execution_runtime_api/*`
- `ProgramAPI::*` -> `AgentAPI::*`
- `ExecutionAPI::*` -> `ExecutionRuntimeAPI::*`
- control-plane value `agent` remains `agent`
- control-plane value `execution_runtime` remains `execution_runtime`
- mailbox routing field `runtime_plane` becomes `control_plane`

## Domain Boundary Decisions

This rename is not just cosmetic. The new `ExecutionRuntime` is the durable
owner of:

- execution-runtime capability payloads and tool catalog
- execution-runtime connection metadata
- execution-runtime process ownership
- execution-runtime connection issuance and lookup
- execution-runtime routing for mailbox delivery and close control

The new model therefore absorbs the old runtime-host semantics instead of
pretending that the previous host/runtime concept still exists under a new
label.

## Deliberate Non-Renames

Not every `execution_*` name should become `executor_*`.

Keep the existing `execution_*` names when they describe execution behavior
rather than the executor host entity itself, for example:

- `ExecutionContract`
- `execution_profiling`
- `provider_execution`
- `Turn` execution snapshots or execution state assembly helpers

These names describe work being executed, not the durable executor identity.
Renaming them would blur the difference between executor ownership and
execution behavior.

## Persistence Model Changes

### Tables

- `execution_sessions` -> `execution_runtime_connections`

### Foreign Keys

- every `execution_session_id` foreign key becomes `execution_runtime_connection_id`
- mailbox and report rows use `target_execution_runtime_id` and
  `leased_to_execution_runtime_connection_id`

### Schema Regeneration

Because the repository explicitly accepts destructive change, baseline
migrations are edited in place and the database is rebuilt from scratch in
`/Users/jasl/Workspaces/Ruby/cybros/core_matrix` with:

```bash
rails db:drop && rm db/schema.rb && rails db:create && rails db:migrate && rails db:reset
```

## Application Structure Changes

### Models And Services

- `app/models/execution_runtime.rb` is the canonical durable runtime model
- `app/models/execution_session.rb` becomes
  `app/models/execution_runtime_connection.rb`
- `app/services/execution_runtimes/*` remains the canonical runtime service namespace
- `app/services/execution_sessions/*` becomes
  `app/services/execution_runtime_connections/*`

### Controller Boundaries

- `app/controllers/program_api/*` becomes `app/controllers/agent_api/*`
- `app/controllers/execution_api/*` becomes `app/controllers/execution_runtime_api/*`
- request authentication helpers, serializers, and test helpers all switch to
  the new naming in one pass

### Mailbox / Control Plane

The control-plane envelope will stop using the word `runtime` for durable
routing. `control_plane` becomes the single durable router field with values
`program` and `executor`. Any payload keys or docs still referring to
`runtime_plane` should be removed rather than aliased.

## Contract Changes

### Registration And Capability Handshake

Agent registration will continue to bind a logical agent agent snapshot and a
separate execution-runtime host identity, but the payload names will change:

- `execution_session_id` -> `execution_runtime_connection_id`
- `runtime_fingerprint` -> `execution_runtime_fingerprint`
- `runtime_kind` -> `execution_runtime_kind`
- `runtime_connection_metadata` -> `execution_runtime_connection_metadata`

### Resource APIs

The executor-facing control/report endpoints move to `/execution_runtime_api/control/*`.
Program-facing transcript, variable, interaction, and tool APIs move to
`/agent_api/*`.

No legacy routes or legacy JSON keys should survive this refactor.

## Test Strategy

The rename should be verified in layers:

1. focused model/service/request tests for renamed host-side entities
2. focused mailbox/control/request tests for renamed contract fields and routes
3. focused integration tests for registration, runtime resource APIs, bundled
   bootstrap, and dummy runtime flows
4. full project verification from the `core_matrix` root

## Risks To Watch

- stale references inside baseline migrations causing schema regeneration to
  fail
- Rails autoloading mismatches after namespace/file renames
- forgotten request spec paths still hitting `/program_api` or
  `/execution_api`
- mailbox serialization still emitting `runtime_plane` or old executor ids
- test helper factories leaking old `execution_runtime` names and making the
  suite inconsistent

## Acceptance Criteria

The change is complete when all of the following are true:

- no production code, tests, or docs under `core_matrix` still refer to
  `ExecutionSession`, `program_api`, `execution_api`, or `runtime_plane`
  except in archived historical docs that intentionally preserve old wording
- the schema contains `execution_runtimes`, `execution_runtime_connections`, and renamed
  foreign keys
- the machine-facing HTTP boundary uses only `agent_api` and `execution_runtime_api`
- registration and control payloads expose only the new
  `execution_runtime_*` names
- the full `core_matrix` verification command set passes on a rebuilt database
