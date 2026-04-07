# Agent / Executor Program Rename Design

## Goal

Replace the current execution-runtime-centered terminology in Core Matrix with
a symmetric `AgentProgram` / `ExecutorProgram` domain model. This is an
intentional destructive change: no compatibility shims, no dual naming, and no
data preservation.

## Approved Scope

- rename the host-side execution entity from `ExecutionRuntime` to
  `ExecutorProgram`
- rename the host-side authenticated session from `ExecutionSession` to
  `ExecutorSession`
- rename the machine-facing API namespaces from `program_api` and
  `execution_api` to `agent_api` and `executor_api`
- rewrite baseline migrations in place instead of adding compatibility
  migrations
- regenerate the local database and `db/schema.rb` from scratch after the
  migration edits
- update tests, scripts, docs, and request payloads to the new language in the
  same change set

## Naming Decisions

### Durable Domain Entities

- `AgentProgram` remains the durable logical agent product
- `AgentProgramVersion` remains the immutable versioned agent payload
- `ExecutorProgram` becomes the durable logical executor host/program identity
- `ExecutorSession` becomes the authenticated live session for an
  `ExecutorProgram`

### New Canonical Field Names

- `default_execution_runtime` -> `default_executor_program`
- `execution_runtime_id` -> `executor_program_id`
- `execution_session_id` -> `executor_session_id`
- `target_execution_runtime_id` -> `target_executor_program_id`
- `leased_to_execution_session_id` -> `leased_to_executor_session_id`
- `runtime_fingerprint` -> `executor_fingerprint`
- `runtime_kind` -> `executor_kind`
- `runtime_connection_metadata` -> `executor_connection_metadata`
- `execution_capability_payload` -> `executor_capability_payload`
- `execution_tool_catalog` -> `executor_tool_catalog`

### HTTP / Protocol Naming

- `/program_api/*` -> `/agent_api/*`
- `/execution_api/*` -> `/executor_api/*`
- `ProgramAPI::*` -> `AgentAPI::*`
- `ExecutionAPI::*` -> `ExecutorAPI::*`
- `program_plane` remains `program_plane`
- `execution_plane` becomes `executor_plane`
- mailbox routing field `runtime_plane` becomes `control_plane`
- mailbox routing value `"execution"` becomes `"executor"`

## Domain Boundary Decisions

This rename is not just cosmetic. The new `ExecutorProgram` is the durable
owner of:

- executor capability payloads and tool catalog
- executor-side connection metadata
- executor-side process ownership
- executor-side session issuance and lookup
- executor-side routing for mailbox delivery and close control

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

- `execution_runtimes` -> `executor_programs`
- `execution_sessions` -> `executor_sessions`

### Foreign Keys

- `agent_programs.default_execution_runtime_id` ->
  `agent_programs.default_executor_program_id`
- every `execution_runtime_id` foreign key becomes `executor_program_id`
- every `execution_session_id` foreign key becomes `executor_session_id`
- mailbox and report rows use `target_executor_program_id` and
  `leased_to_executor_session_id`

### Schema Regeneration

Because the repository explicitly accepts destructive change, baseline
migrations are edited in place and the database is rebuilt from scratch in
`/Users/jasl/Workspaces/Ruby/cybros/core_matrix` with:

```bash
rails db:drop && rm db/schema.rb && rails db:create && rails db:migrate && rails db:reset
```

## Application Structure Changes

### Models And Services

- `app/models/execution_runtime.rb` becomes
  `app/models/executor_program.rb`
- `app/models/execution_session.rb` becomes
  `app/models/executor_session.rb`
- `app/services/execution_runtimes/*` becomes
  `app/services/executor_programs/*`
- `app/services/execution_sessions/*` becomes
  `app/services/executor_sessions/*`

### Controller Boundaries

- `app/controllers/program_api/*` becomes `app/controllers/agent_api/*`
- `app/controllers/execution_api/*` becomes `app/controllers/executor_api/*`
- request authentication helpers, serializers, and test helpers all switch to
  the new naming in one pass

### Mailbox / Control Plane

The control-plane envelope will stop using the word `runtime` for durable
routing. `control_plane` becomes the single durable router field with values
`program` and `executor`. Any payload keys or docs still referring to
`runtime_plane` should be removed rather than aliased.

## Contract Changes

### Registration And Capability Handshake

Agent registration will continue to bind a logical agent program version and a
separate executor-side host identity, but the payload names will change:

- `execution_runtime_id` -> `executor_program_id`
- `execution_session_id` -> `executor_session_id`
- `execution_plane` -> `executor_plane`
- `runtime_fingerprint` -> `executor_fingerprint`
- `runtime_kind` -> `executor_kind`
- `runtime_connection_metadata` -> `executor_connection_metadata`

### Resource APIs

The executor-facing control/report endpoints move to `/executor_api/control/*`.
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
  `ExecutionRuntime`, `ExecutionSession`, `program_api`, or `execution_api`
  except in archived historical docs that intentionally preserve old wording
- the schema contains `executor_programs`, `executor_sessions`, and renamed
  foreign keys
- the machine-facing HTTP boundary uses only `agent_api` and `executor_api`
- registration and control payloads expose only the new `executor_*` names
- the full `core_matrix` verification command set passes on a rebuilt database
