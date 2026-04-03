# User Bindings And Private Workspaces

## Purpose

Task 04.1 establishes the user-owned chain between the installation-level agent
registry and private workspaces: `User -> UserProgramBinding -> Workspace`.

## Aggregate Responsibilities

### UserProgramBinding

- A binding links one user to one logical `AgentProgram`.
- One binding exists at most once for a given user-agent pair.
- Bindings stay inside one installation and inherit that boundary from both the
  user and the agent program.
- Personal agent programs may only be bound by their owner user.
- Binding presence represents that the agent is enabled for that user in v1.

### Workspace

- `Workspace` belongs to exactly one binding and exactly one user.
- Workspaces are always private in v1.
- A binding may have many workspaces, but only one default workspace.
- Workspace ownership follows the binding owner and installation boundary.

## Services

### `UserProgramBindings::Enable`

- Enables an agent for a user by reusing or creating the unique binding row.
- Rejects cross-installation binding attempts.
- Rejects enabling another user's personal agent program.
- Ensures the binding has a default workspace.

### `Workspaces::CreateDefault`

- Creates the first default workspace for a binding when missing.
- Reuses the existing default workspace when called again.
- Derives workspace ownership from the binding instead of accepting ad hoc
  user or installation arguments.

## Invariants

- `Workspace` remains private and user-owned.
- Default workspace uniqueness is scoped to `user_program_binding_id`, not the
  installation.
- Service orchestration owns enable/default-workspace side effects; models do
  not use callbacks to create default workspaces.
- Bundled-agent bootstrap is still deferred to Task 04.2.

## Failure Modes

- Cross-installation bindings are invalid at both the model and service
  boundary.
- Attempting to enable another user's personal agent raises
  `UserProgramBindings::Enable::AccessDenied`.
- A second default workspace for the same binding is invalid.
