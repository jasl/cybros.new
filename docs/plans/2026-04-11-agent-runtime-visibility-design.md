# Agent And Execution Runtime Visibility Reset Design

**Date:** 2026-04-11

## Goal

Replace the old `Agent` visibility model with a destructive, installation-local
`public/private` model, extend the same model to `ExecutionRuntime`, and make
resource usability follow the current visibility state without keeping
compatibility shims.

## Scope

This design applies to:

- `core_matrix` domain models, queries, services, tests, and docs
- bundled bootstrap defaults for `Fenix` and `Nexus`
- app-facing workspace and conversation usability rules that depend on the
  bound `Agent` and `ExecutionRuntime`

This design does not apply to:

- actor authorization in services
- API/UI authorization implementation details
- multi-user data isolation inside `Fenix` or `Nexus`
- backward compatibility for old schema values or existing databases

The database will be reset after the schema rewrite.

## Terminology

- `public`: visible and usable by any user in the same installation
- `private`: visible and usable only by the owner user
- `provisioning_origin`:
  - `system`
  - `user_created`

`Workspace` and `Conversation` stay private user resources. Their privacy model
does not change. Conversation read-only publication remains a separate feature.

## Target Model

Both `Agent` and `ExecutionRuntime` will use the same three fields:

- `visibility`
- `owner_user_id`
- `provisioning_origin`

Allowed `visibility` values:

- `public`
- `private`

Allowed `provisioning_origin` values:

- `system`
- `user_created`

## Valid State Combinations

Only these combinations are valid:

1. Preinstalled public resource
   - `visibility = public`
   - `owner_user_id = nil`
   - `provisioning_origin = system`
2. User-created public resource
   - `visibility = public`
   - `owner_user_id != nil`
   - `provisioning_origin = user_created`
3. User-created private resource
   - `visibility = private`
   - `owner_user_id != nil`
   - `provisioning_origin = user_created`

All other combinations are invalid.

## Domain Invariants

These rules stay in model/service code as data and business invariants:

- `owner_user` must belong to the same installation as the resource.
- `private` requires `owner_user`.
- `system` requires `public`.
- `system` requires `owner_user = nil`.
- `owner_user = nil` requires `provisioning_origin = system`.
- ownerless resources cannot be switched to `private`.

No general actor authorization framework is enforced at the service layer.
Later API/UI authorization should use `Pundit` by default. This batch only
ensures that app-facing lists and entry points do not expose resources that are
no longer usable under the current visibility state.

## Bootstrap Rules

Bundled `Fenix` and bundled `Nexus` are modeled as:

- `visibility = public`
- `owner_user_id = nil`
- `provisioning_origin = system`

This makes preinstalled, ownerless public resources legal while preventing the
same shape for user-created resources.

## Usability Rules

### Agents

A user may see and use an `Agent` when:

- the agent belongs to the same installation
- the agent is active
- the agent is `public`
- or the agent is `private` and `owner_user_id == user.id`

### Execution Runtimes

A user may see and use an `ExecutionRuntime` when:

- the runtime belongs to the same installation
- the runtime is active
- the runtime is `public`
- or the runtime is `private` and `owner_user_id == user.id`

### Workspace And Conversation Access

`Workspace` and `Conversation` remain user-owned private resources, but their
continued usability depends on the current visibility of the bound resources.

A workspace remains accessible only when:

- `workspace.user_id == current_user.id`
- and its bound `Agent` is still usable by that user

A conversation remains accessible only when:

- its workspace is still accessible
- and its selected `ExecutionRuntime`, if any, is still usable by that user

This means a `public -> private` visibility change does not delete old
workspaces or conversations, but non-owner users lose access immediately.

## Query Direction

Current `Agent` list queries that use `global/personal` semantics are replaced
with explicit `public/private` visibility queries.

`ExecutionRuntime` gets a symmetric visible-to-user query instead of relying on
installation-wide visibility by default.

Avoid bare Rails enum helpers named `public` or `private`. Database values stay
`public/private`, but model helpers and scopes must use prefixes, suffixes, or
explicit scopes to avoid Ruby method-name collisions.

## Runtime And Agent Data Responsibility

When visibility changes:

- `CoreMatrix` updates access semantics only
- `Fenix` and `Nexus` are not notified
- runtime-local or agent-local multi-user data is not cleaned up by contract

This is intentional. Visibility changes affect CoreMatrix access only.

## Expected Code Impact

Primary code paths that must move together:

- `Agent`
- `ExecutionRuntime`
- `UserAgentBinding`
- bundled bootstrap
- agent visible-to-user query
- new execution-runtime visible-to-user query
- app-facing workspace and conversation access entry points
- tests, helpers, seeds, and docs that still use `global/personal`

## Verification

The implementation is complete only when:

- no `global/personal` visibility semantics remain in active code
- bundled bootstrap creates only valid `system/public/ownerless` resources
- non-owner access is denied after a `public -> private` change
- `core_matrix` schema is rebuilt from scratch
- acceptance and test helpers reflect the new visibility model

`core_matrix` schema reset command:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
rails db:drop && rm db/schema.rb && rails db:create && rails db:migrate && rails db:reset
```
