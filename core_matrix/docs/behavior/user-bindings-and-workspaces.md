# User Bindings And Private Workspaces

## Purpose

Task 04.1 establishes the user-owned enablement and workspace contract between
the installation-level agent registry and private workspaces.

The current landed shape is:

- `UserAgentBinding` remains the enablement and preference aggregate for one
  user-agent pair
- `Workspace` is the durable working-context root keyed by
  `(installation_id, user_id, agent_id)`

## Aggregate Responsibilities

### UserAgentBinding

- A binding links one user to one logical `Agent`.
- One binding exists at most once for a given user-agent pair.
- Bindings stay inside one installation and inherit that boundary from both the
  user and the agent.
- Private agents may only be bound by their owner user.
- Binding presence represents that the agent is enabled for that user in v1.
- Bindings no longer own workspace identity or default-workspace uniqueness.

### Workspace

- `Workspace` belongs to exactly one user and one logical `Agent`.
- Workspaces are always private in v1.
- One `(installation_id, user_id, agent_id)` tuple may have many workspaces,
  but only one default workspace.
- Workspace ownership follows the workspace row's own `user_id`, `agent_id`,
  and installation boundary.
- `Workspace` may optionally pin a default `ExecutionRuntime`.
- That workspace-level default runtime seeds the current execution runtime for
  new conversations unless an explicit initial runtime override is supplied.
- Follow-up turns then continue from the conversation current execution epoch
  rather than re-deriving continuity from prior turns.

## Services

### `UserAgentBindings::Enable`

- Enables an agent for a user by reusing or creating the unique binding row.
- Rejects cross-installation binding attempts.
- Rejects enabling another user's private agent.
- Returns a default workspace reference without eagerly creating a real
  workspace row.
- Resolves that default workspace reference through
  `Workspaces::ResolveDefaultReference`, not through a binding-owned workspace
  row.

### `Workspaces::CreateDefault`

- Creates the first default workspace for a binding when missing.
- Reuses the existing default workspace when called again.
- Derives workspace ownership from the user-agent pair instead of accepting ad
  hoc installation arguments.
- Seeds the workspace default execution runtime from the bound agent's current
  `default_execution_runtime`.

### `Workspaces::ResolveDefaultReference`

- Resolves the app-facing default workspace reference from
  `(installation_id, user_id, agent_id, is_default = true)`.
- Returns `state: "virtual"` until a real default workspace row exists.
- Returns `state: "materialized"` once the default workspace has been created.
- Keeps read paths non-materializing: home and list surfaces may return a
  virtual default reference without creating a workspace row.

### `Workspaces::MaterializeDefault`

- Creates the first real default workspace on first substantive use.
- Is idempotent for repeated calls against the same user-agent pair.

## Invariants

- `Workspace` remains private and user-owned.
- Workspace access still depends on agent usability; a workspace disappears
  from owner-facing lists when its logical `Agent` is no longer visible to that
  user.
- Workspace access does not depend on any execution runtime being present or
  currently usable.
- Default workspace uniqueness is scoped to
  `(installation_id, user_id, agent_id, is_default = true)`.
- Service orchestration owns enable/default-workspace side effects; models do
  not use callbacks to create default workspaces.
- Binding enablement does not eagerly create a default workspace row.
- Bundled-agent bootstrap is still deferred to Task 04.2.

## Failure Modes

- Cross-installation bindings are invalid at both the model and service
  boundary.
- Attempting to enable another user's private agent raises
  `UserAgentBindings::Enable::AccessDenied`.
- A second default workspace for the same user-agent pair is invalid.
