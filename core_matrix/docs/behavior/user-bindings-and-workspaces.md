# User Workspaces And Mounted Agents

## Purpose

The legacy `UserAgentBinding` topology has been removed.

The current durable shape is:

- `Workspace` is the user-owned root.
- `WorkspaceAgent` is the mounted-agent aggregate for one
  `(workspace_id, agent_id)` pair.

## Aggregate Responsibilities

### `Workspace`

- belongs to exactly one user inside one installation
- remains private in v1
- allows at most one default workspace per `(installation_id, user_id)`
- stays visible to its owner when all remaining mounts are revoked
- becomes inaccessible when it still has active mounts but none of those agents
  are visible to the owner anymore

### `WorkspaceAgent`

- mounts one logical `Agent` into one `Workspace`
- allows at most one active mount per `(workspace_id, agent_id)`
- may pin a default `ExecutionRuntime`
- carries mount-scoped capability policy through `disabled_capabilities`
- carries mount-scoped entry-surface policy
- transitions through `active`, `revoked`, and `retired`
- locks existing conversations when revoked instead of deleting them

## Services

### `Workspaces::CreateDefault`

- creates the default workspace for a user when missing
- reuses the existing default workspace when called again
- ensures the requested agent is mounted into that workspace as an active
  `WorkspaceAgent`
- seeds the mount default runtime from the agent default runtime

### `Workspaces::ResolveDefaultReference`

- resolves a concrete default workspace reference from `(user, agent)`
- returns `nil` when no default workspace has been materialized
- returns `state: "materialized"` once the default workspace and active mount
  exist

### `Workspaces::MaterializeDefault`

- creates the first real default workspace on first substantive use
- is idempotent for repeated calls against the same `(user, agent)` pair

## Invariants

- workspaces are private and user-owned
- active mount visibility gates workspace and conversation accessibility
- revoked mounts do not hide retained workspaces or conversations
- execution runtime visibility does not gate workspace or conversation
  accessibility
- default workspace uniqueness is scoped to `(installation_id, user_id,
  is_default = true)`
- active mount uniqueness is scoped to `(workspace_id, agent_id)`

## Failure Modes

- cross-installation workspace mounts are invalid
- a second default workspace for the same user is invalid
- a second active mount for the same `(workspace, agent)` pair is invalid
