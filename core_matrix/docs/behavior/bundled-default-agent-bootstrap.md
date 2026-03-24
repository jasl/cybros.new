# Bundled Default-Agent Bootstrap

## Purpose

Task 04.2 adds the opt-in bootstrap path for the packaged bundled runtime. When
explicitly configured, first-admin bootstrap reconciles the bundled agent
registry rows and then binds that logical agent to the first admin through the
existing binding and workspace services.

## Services

### `Installations::RegisterBundledAgentRuntime`

- Reconciles the packaged runtime into `AgentInstallation`,
  `ExecutionEnvironment`, `AgentDeployment`, and `CapabilitySnapshot`.
- Reuses existing logical and deployment rows instead of duplicating them on
  repeated calls.
- Does not create user bindings or workspaces.
- Returns `nil` when bundled bootstrap is not enabled in configuration.

### `Installations::BootstrapBundledAgentBinding`

- Runs only when bundled bootstrap is explicitly enabled.
- Calls bundled runtime reconciliation before any user binding is created.
- Composes `UserAgentBindings::Enable` so default workspace creation continues
  to flow through the existing workspace service.

### `Installations::BootstrapFirstAdmin`

- Remains the installation entry point for first-admin creation.
- After the installation, identity, user, and bootstrap audit row exist, it
  optionally composes bundled runtime registration plus first-admin binding.

## Invariants

- Bundled bootstrap stays opt-in through configuration.
- Registry reconciliation happens before first-admin binding.
- The packaged runtime is modeled with the same registry aggregates as external
  runtimes; no special-case domain tables are introduced.
- Binding and default workspace creation continue to reuse Task 04.1 services.

## Failure Modes

- Disabled bundled bootstrap leaves registry, binding, and workspace rows
  untouched.
- Repeated bundled runtime reconciliation must not duplicate logical agent or
  deployment rows.
- Bundled bootstrap remains scoped to the single packaged runtime and does not
  act as a generic connector layer.
