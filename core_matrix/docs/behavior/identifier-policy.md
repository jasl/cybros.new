# Identifier Policy

## Purpose

Core Matrix keeps internal relational identity and external resource identity
separate.

The database continues to use compact internal `bigint` primary keys for
foreign keys, joins, and internal service wiring. Public and agent-facing
contracts use opaque `public_id` values instead.

## PostgreSQL Baseline

- Core Matrix requires PostgreSQL 18 for the database-native `uuidv7()`
  default used by `public_id`.
- CI must pin `postgres:18`; support is defined by the pinned service image,
  not by ambient runner defaults.

## In-Scope Resources

The following resources carry `public_id` and are allowed to cross external or
agent-facing boundaries:

- `User`
- `Invitation`
- `Session`
- `Workspace`
- `AgentInstallation`
- `ExecutionEnvironment`
- `AgentDeployment`
- `Conversation`
- `Turn`
- `Message`
- `MessageAttachment`
- `WorkflowRun`
- `WorkflowNode`
- `HumanInteractionRequest`
- `Publication`

## Boundary Rules

- external lookup parameters must resolve resources by `public_id`
- public payloads must emit `public_id`, even when contract field names remain
  `id` or `*_id`
- internal service wiring, associations, and database joins continue to use
  internal `bigint` ids after boundary lookup
- external boundaries must not accept mixed fallback logic that also resolves
  raw internal ids
- canonical-variable payloads must not expose canonical-variable row ids
  because `CanonicalVariable` is not an external resource

## Runtime Payload Rules

- machine-facing HTTP APIs use `public_id` for resource references
- workflow execution snapshots and other agent-facing runtime payloads also use
  `public_id` for resource references
- when `turn_origin.source_ref_type` points at an in-scope external resource,
  `turn_origin.source_ref_id` must carry that resource's `public_id`
- resources that do not have `public_id` must not leak raw internal row ids
  through agent-facing payloads

## Ordering Rule

- `uuidv7` improves external identifier locality, but it is not the semantic
  ordering contract
- transcript pagination, workflow ordering, and business sequencing still use
  explicit fields such as `created_at`, `sequence`, `ordinal`, or domain
  cursors derived from the visible resource list

## Explicit Exclusions

The following table families remain internal-only in Phase 1 and do not gain
`public_id` just for symmetry:

- join tables
- closure tables
- overlay/projection tables
- usage and profiling facts
- execution leases
- workflow edges and node events
- framework-owned tables such as Active Storage, Solid Queue, and Action Cable

## Developer Rule

- do not expose internal `id` as a durable product, API, or runtime contract
- when adding a new external resource, decide explicitly whether it needs
  `public_id`; do not default to exposing `bigint`
