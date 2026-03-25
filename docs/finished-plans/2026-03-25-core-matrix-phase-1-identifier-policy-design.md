# Core Matrix Phase 1 Identifier Policy Design

## Status

- approved on `2026-03-25`
- scope owner: `core_matrix`
- source: Phase 1 review follow-up design discussion about durable identifier
  policy before non-empty datasets land

## Goal

Define a durable identifier policy for `core_matrix` while the database is
still disposable, so external and user-visible surfaces use opaque stable
identifiers without forcing UUID primary keys across the entire relational
substrate.

## Decision Summary

- `core_matrix` keeps `bigint` primary keys for internal relational ownership,
  foreign keys, batch processing, and append-only runtime storage.
- Resources that cross an external, user-facing, or long-lived operator-facing
  boundary add `public_id :uuid`.
- When `core_matrix` generates UUID-backed public identifiers, it uses
  PostgreSQL 18 `uuidv7()` rather than random UUID generation.
- `public_id` presence is enforced by database constraints and defaults, not by
  a model-level presence validation that would run before the database default
  fires.
- `public_id` is an opaque reference identifier, not a business ordering field;
  ordering remains anchored on explicit fields such as `created_at`,
  `sequence`, or other domain counters.
- Rails and framework-owned infrastructure tables such as Active Storage,
  queue, and cable remain outside this policy unless `core_matrix` later adds a
  domain wrapper that needs its own public identifier.
- PostgreSQL 18 becomes the explicit minimum supported database version for
  `core_matrix`, and CI must pin a PostgreSQL 18 service image instead of
  relying on floating defaults.

## Why Not UUID Primary Keys Everywhere

The reviewed schema is currently all-`bigint`, and the current Phase 1 design
did not reserve UUID primary keys as a substrate rule. The core requirement
discovered during review is not "every table must look modern"; it is "public
resources must not leak enumerable internal IDs."

For this system, blanket UUID primary keys would couple two separate concerns:

1. internal relational identity and storage locality
2. external opaque resource identity

Keeping `bigint` internally while adding `public_id` at boundary resources
solves the actual product concern with less index cost, less foreign-key churn,
and less accidental coupling between external contracts and storage internals.

## Resource Scope

The rule for adding `public_id` is based on whether a table models a resource
that outside callers, users, operators, or durable links may reference.

### First implementation batch

The first implementation batch should treat these tables as in-scope for
`public_id`:

- `users`
- `invitations`
- `sessions`
- `workspaces`
- `agent_installations`
- `agent_deployments`
- `execution_environments`
- `conversations`
- `turns`
- `messages`
- `message_attachments`
- `human_interaction_requests`
- `workflow_runs`
- `workflow_nodes`
- `publications`

Tables such as `workflow_artifacts` may add `public_id` later if they become
directly addressable from external APIs, audit UIs, or operator tooling, but
they are not required for the initial adoption.

### Explicit exclusions

These table classes should not receive `public_id` in the initial policy:

- closure tables
- join tables
- overlay tables
- event tables
- rollup tables
- snapshot tables
- lease tables
- framework-owned infrastructure tables

Concrete examples include:

- `conversation_closures`
- `conversation_message_visibilities`
- `usage_rollups`
- `capability_snapshots`
- `execution_leases`
- `workflow_edges`
- `active_storage_*`

If a future resource only exists to support internal lineage, projection,
ledgering, or performance, it should keep the default internal `bigint`
identity only.

## Boundary Rules

- Public HTTP endpoints, serialized payloads, future UI routes, share links,
  downloads, and audit displays must use `public_id`, not internal `id`.
- Public contract field names may stay resource-oriented, including `*_id`
  names, but the values carried in those fields must be `public_id` values once
  a resource is in scope for this policy.
- Public request lookup paths must resolve resources by `public_id`.
- Internal services, transactions, foreign-key relationships, and background
  jobs may continue using internal `bigint` IDs.
- Do not add mixed public lookup semantics such as "accept either `id` or
  `public_id`" on external boundaries.
- If a domain attachment needs an opaque external reference, that reference
  belongs on the domain table such as `message_attachments`, not on the
  framework tables underneath Active Storage.

## Ordering Rule

`uuidv7()` is chosen because it gives time-ordered opaque identifiers with
better index locality than random UUIDs. That does not make `public_id` the
canonical ordering field for business behavior.

The application must continue to order by explicit domain fields:

- `created_at` for resource chronology
- `sequence` or version columns for append-only or conversation-local order
- domain-specific counters where the behavior already depends on them

This prevents hidden ordering assumptions from leaking into APIs, tests, and
query objects.

## Database And CI Baseline

- PostgreSQL 18 is the minimum supported database version for `core_matrix`.
- New `public_id` defaults should rely on the built-in PostgreSQL 18
  `uuidv7()` function.
- The GitHub Actions workflow must pin a PostgreSQL 18 service container, for
  example `postgres:18`, instead of using a floating `postgres` image.
- The CI rule is independent of the Ubuntu runner image. The current workflow
  uses a Docker service container, so OS package defaults do not control the
  database version used in CI.

## Documentation Policy

- Record this decision as a dedicated active design record under `docs/plans`.
- When implementation lands, update `core_matrix/docs/behavior/` with the
  authoritative runtime rule for `public_id` coverage and external lookup
  behavior.
- Keep the monorepo root `AGENTS.md` concise. If it is updated, it should only
  add a short cross-reference or guardrail such as "for `core_matrix`, treat
  `public_id` as the only public resource identifier."
- Do not rewrite historical `docs/finished-plans` records just to pretend this
  identifier policy existed during the original Phase 1 landing. If later work
  needs historical traceability, reference this design record from new active
  planning or behavior docs instead.

## Migration Strategy

Because the database is currently empty and disposable, the first adoption pass
can use the lowest-friction path:

- edit the existing Phase 1 create-table migrations for the in-scope resource
  tables
- regenerate `schema.rb`
- reset development and test databases as needed

No backfill plan is needed for the current adoption window. Once non-disposable
data exists, additional `public_id` adoption must switch to additive
forward-only migrations plus data backfill.

## Implementation Guardrails

- Do not change existing internal primary keys to UUID.
- Do not add `public_id` speculatively to every table.
- Do not use `public_id` as a hidden replacement for ordering fields.
- Do not change Active Storage internals just to satisfy identifier symmetry.
- New externally addressable resource tables should add `public_id` in their
  first migration instead of treating it as optional polish for a later phase.
- Keep the first implementation batch focused on the approved resource set and
  the documentation needed to make the rule durable for later work.

## Reference Findings

- The current `core_matrix` schema and create-table migrations are
  overwhelmingly `bigint`-based, so UUID primary keys would be a full-schema
  substrate rewrite rather than a small tactical correction.
- The local development database reports PostgreSQL `18.3`, confirming that the
  current workstation can exercise `uuidv7()` directly.
- Rails PostgreSQL guides document first-class UUID column and primary-key
  support.
- PostgreSQL current documentation exposes `uuidv7()` as a built-in function
  and clarifies that the `uuid` type can store values generated by different
  UUID versions.
- GitHub Actions PostgreSQL service-container configuration is controlled by
  the configured image tag, not by Ubuntu package defaults on the runner.
