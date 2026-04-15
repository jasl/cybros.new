# Bundled Default-Agent Bootstrap

## Purpose

Bundled bootstrap is opt-in. When enabled, first-admin bootstrap:

1. reconciles the packaged bundled agent/runtime registry rows
2. materializes the first admin's default workspace
3. mounts the bundled agent into that workspace as an active `WorkspaceAgent`

## Services

### `Installations::RegisterBundledAgentRuntime`

- reconciles `Agent`, `ExecutionRuntime`, `AgentDefinitionVersion`,
  `AgentConnection`, and `ExecutionRuntimeConnection`
- keeps bundled runtime registration idempotent
- does not create user-owned workspaces or mounts
- returns `nil` when bundled bootstrap is disabled

### `Installations::BootstrapBundledAgentBinding`

- runs only when bundled bootstrap is enabled
- performs runtime reconciliation before workspace creation
- materializes the admin default workspace through `Workspaces::CreateDefault`
- ensures the bundled agent mount is active on that workspace
- returns a concrete `default_workspace_ref` with `state: "materialized"`

### `Installations::BootstrapFirstAdmin`

- remains the installation entry point for first-admin creation
- optionally composes bundled runtime reconciliation plus first-admin workspace
  bootstrap after the installation, identity, user, and audit row exist

## Invariants

- bundled bootstrap stays opt-in
- registry reconciliation happens before workspace creation
- bundled runtime registration remains idempotent
- first-admin bootstrap materializes at most one default workspace and one
  active bundled mount for that user

## Failure Modes

- disabled bundled bootstrap leaves registry, workspace, and mount rows
  untouched
- repeated bundled runtime reconciliation must not duplicate logical registry
  rows
