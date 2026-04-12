# User Bindings And Private Workspaces

## Purpose

Task 04.1 establishes the user-owned chain between the installation-level agent
registry and private workspaces: `User -> UserAgentBinding -> Workspace`.

## Aggregate Responsibilities

### UserAgentBinding

- A binding links one user to one logical `Agent`.
- One binding exists at most once for a given user-agent pair.
- Bindings stay inside one installation and inherit that boundary from both the
  user and the agent.
- Private agents may only be bound by their owner user.
- Binding presence represents that the agent is enabled for that user in v1.

### Workspace

- `Workspace` belongs to exactly one binding and exactly one user.
- Workspaces are always private in v1.
- A binding may have many workspaces, but only one default workspace.
- Workspace ownership follows the binding owner and installation boundary.
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

### `Workspaces::CreateDefault`

- Creates the first default workspace for a binding when missing.
- Reuses the existing default workspace when called again.
- Derives workspace ownership from the binding instead of accepting ad hoc
  user or installation arguments.
- Seeds the workspace default execution runtime from the bound agent's current
  `default_execution_runtime`.

### `Workspaces::BuildDefaultReference`

- Builds the app-facing default workspace reference for a binding.
- Returns `state: "virtual"` until a real default workspace row exists.
- Returns `state: "materialized"` once the default workspace has been created.

### `Workspaces::MaterializeDefault`

- Creates the first real default workspace on first substantive use.
- Is idempotent for repeated calls against the same binding.

## Invariants

- `Workspace` remains private and user-owned.
- Workspace access does not depend on any execution runtime being present or
  currently usable.
- Default workspace uniqueness is scoped to `user_agent_binding_id`, not the
  installation.
- Service orchestration owns enable/default-workspace side effects; models do
  not use callbacks to create default workspaces.
- Binding enablement does not eagerly create a default workspace row.
- Bundled-agent bootstrap is still deferred to Task 04.2.

## Failure Modes

- Cross-installation bindings are invalid at both the model and service
  boundary.
- Attempting to enable another user's private agent raises
  `UserAgentBindings::Enable::AccessDenied`.
- A second default workspace for the same binding is invalid.
