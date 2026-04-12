# Bundled Default-Agent Bootstrap

## Purpose

Task 04.2 adds the opt-in bootstrap path for the packaged bundled runtime. When
explicitly configured, first-admin bootstrap reconciles the bundled agent
registry rows and then binds that logical agent to the first admin through the
existing binding and workspace services.

## Services

### `Installations::RegisterBundledAgentRuntime`

- Reconciles the packaged runtime into `Agent`,
  `ExecutionRuntime`, `AgentDefinitionVersion`, `AgentConnection`, and
  `ExecutionRuntimeConnection`.
- Treats `ExecutionRuntime` as the stable execution host and rotates
  `AgentDefinitionVersion` when the bundled runtime release fingerprint changes.
- Reuses existing logical and agent-definition-version rows instead of duplicating them on
  repeated calls.
- Concurrent bundled-runtime reconciliation serializes around the logical
  agent and execution runtime so repeated passes reuse the same version and
  session rows without duplicate-key races.
- Uses `execution_runtime_connection_metadata` for the execution-runtime
  connection surface and `endpoint_metadata` for the agent connection surface;
  the config names intentionally mirror the two distinct planes.
- Does not create user bindings or workspaces.
- Returns `nil` when bundled bootstrap is not enabled in configuration.

### `Installations::BootstrapBundledAgentBinding`

- Runs only when bundled bootstrap is explicitly enabled.
- Calls bundled runtime reconciliation before any user binding is created.
- Composes `UserAgentBindings::Enable` so the binding is created and the
  default workspace reference remains virtual until first real use.

### `Installations::BootstrapFirstAdmin`

- Remains the installation entry point for first-admin creation.
- After the installation, identity, user, and bootstrap audit row exist, it
  optionally composes bundled runtime registration plus first-admin binding.

## Invariants

- Bundled bootstrap stays opt-in through configuration.
- Registry reconciliation happens before first-admin binding.
- The packaged runtime is modeled with the same registry aggregates as external
  runtimes; no special-case domain tables are introduced.
- Binding enablement continues to reuse Task 04.1 services, but default
  workspace rows remain lazily materialized.

## Failure Modes

- Disabled bundled bootstrap leaves registry, binding, and workspace rows
  untouched.
- Repeated bundled runtime reconciliation must not duplicate logical agent or
  agent-definition-version rows.
- Bundled bootstrap remains scoped to the single packaged runtime and does not
  act as a generic connector layer.
