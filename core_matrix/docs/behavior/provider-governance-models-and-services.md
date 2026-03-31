# Provider Governance Models And Services

## Purpose

Provider governance rows remain the installation-scoped SQL layer that sits on
top of the config-backed provider catalog. They store mutable installation
facts only: credentials, entitlements, and policies.

The catalog declares whether a provider requires credentials and which
credential kind it expects. Governance rows answer whether this installation
currently satisfies those declared requirements.

Phase 2 also adds an installation-scoped durable capability-governance layer
for tool exposure and execution audit. Provider availability and tool
governance stay separate concerns:

- provider governance answers whether a candidate provider-model pair is usable
- capability governance answers which logical tool implementation is allowed,
  frozen, and later invoked for one task attempt

## Aggregate Responsibilities

### ProviderCredential

- `ProviderCredential` stores secret connection material for one provider handle
  and credential kind inside one installation.
- Secret material is encrypted at rest with Rails Active Record Encryption.
- Credential rows track rotation time separately from general metadata.
- One installation cannot hold duplicate rows for the same
  `provider_handle + credential_kind` pair.
- The model itself keeps only structural validation; provider-handle membership
  in the catalog is enforced at the write-service boundary.

### ProviderEntitlement

- `ProviderEntitlement` stores subscription or quota facts for one provider
  handle inside one installation.
- Entitlements are keyed so one provider can hold more than one tracked
  entitlement shape over time.
- The current baseline supports explicit window kinds including
  `rolling_five_hours`.
- Rolling five-hour entitlements persist their derived `window_seconds`
  explicitly as `18_000`.
- The model itself keeps only structural validation; provider-handle membership
  in the catalog is enforced at the write-service boundary.

### ProviderPolicy

- `ProviderPolicy` stores enablement and provider-side selection defaults for
  one provider handle inside one installation.
- One installation keeps at most one policy row per provider handle.
- `enabled = false` is the installation-scoped dynamic override for temporarily
  disabling an otherwise catalog-visible provider.
- The model itself keeps only structural validation; provider-handle membership
  in the catalog is enforced at the write-service boundary.

### ProviderRequestControl

- `ProviderRequestControl` stores durable per-installation/provider admission
  state such as the current cooldown window after an upstream rate limit.
- One installation keeps at most one control row per provider handle.
- This row is runtime coordination state, not user-managed configuration.

### ProviderRequestLease

- `ProviderRequestLease` stores one admitted in-flight provider request.
- Active leases enforce the hard per-provider concurrency cap declared in the
  catalog's `admission_control` block.
- Expired or completed requests release their lease explicitly in SQL.

## Services

### `ProviderCredentials::UpsertSecret`

- Upserts one `ProviderCredential` by installation, provider handle, and
  credential kind.
- Validates the provider handle against the current catalog snapshot before the
  row is saved.
- Rotates the encrypted secret and `last_rotated_at` timestamp together.
- Writes `provider_credential.upserted` audit rows without storing plaintext
  secret material in audit metadata.

### `ProviderEntitlements::Upsert`

- Upserts one `ProviderEntitlement` by installation, provider handle, and
  entitlement key.
- Validates the provider handle against the current catalog snapshot before the
  row is saved.
- Derives `window_seconds` from the declared `window_kind`.
- Writes `provider_entitlement.upserted` audit rows.

### `ProviderPolicies::Upsert`

- Upserts one `ProviderPolicy` by installation and provider handle.
- Validates the provider handle against the current catalog snapshot before the
  row is saved.
- Persists provider enablement and selection-default settings through one
  audited boundary.
- Writes `provider_policy.upserted` audit rows.

### `ProviderExecution::ProviderRequestGovernor`

- Enforces provider `admission_control` limits through durable SQL state.
- Creates one `ProviderRequestLease` for each admitted request.
- Blocks new requests when the active lease count reaches
  `max_concurrent_requests`.
- Writes provider cooldown state into `ProviderRequestControl` after upstream
  `429` responses.

### `ProviderCatalog::EffectiveCatalog#availability`

- Resolves one provider-qualified model against both the catalog and the
  installation-scoped governance rows.
- Returns whether the candidate is currently usable plus a structured
  `reason_key` when it is not.
- Applies the provider-availability checks in this order:
  1. provider exists in the catalog
  2. model exists under that provider
  3. model `enabled` flag is true
  4. provider `enabled` flag is true
  5. current environment is included in the provider `environments`
  6. installation policy has not disabled the provider
  7. an active provider entitlement exists
  8. a matching credential exists when `requires_credential: true`

## Unified Capability Governance

### Aggregate Responsibilities

#### `ImplementationSource`

- `ImplementationSource` records the durable origin of one family of tool
  implementations inside an installation
- the current source kinds are:
  - `core_matrix`
  - `execution_environment`
  - `agent`
  - `kernel`
  - `mcp`
- this row is installation-scoped audit metadata, not an agent-facing
  transport contract

#### `ToolDefinition`

- `ToolDefinition` records one logical governed tool for one
  `CapabilitySnapshot`
- each definition keeps:
  - logical `tool_name`
  - effective `tool_kind`
  - `governance_mode`
  - policy metadata for the snapshot-default implementation
- the current governance modes are:
  - `reserved`: only the Core Matrix-owned implementation may be bound
  - `whitelist_only`: the environment-approved default implementation must be
    used
  - `replaceable`: alternate implementations under the same logical tool name
    may be selected explicitly

#### `ToolImplementation`

- `ToolImplementation` records one concrete implementation candidate for one
  logical governed tool
- the row stores the durable implementation reference plus schema, streaming,
  and idempotency metadata
- exactly one implementation is marked `default_for_snapshot` for each
  `ToolDefinition`

#### `ToolBinding`

- `ToolBinding` freezes one `ToolDefinition -> ToolImplementation` decision on
  one `AgentTaskRun`
- bindings are created automatically when `AgentTaskRun` is created
- the binding stores the freeze reason plus the capability-snapshot metadata
  used to make the decision
- retries inside the same task attempt reuse the same binding
- new attempts receive a fresh binding set instead of mutating the previous
  attempt's rows

#### `ToolInvocation`

- `ToolInvocation` records the lifecycle of one bound tool use
- runtime-owned, environment-approved, and Core Matrix-reserved tools all use
  the same invocation row shape
- invocation history therefore stays source-agnostic:
  there is no separate durable table for reserved tools versus agent-exposed
  tools

### Services

#### `ToolBindings::ProjectCapabilitySnapshot`

- projects durable governed rows from one `CapabilitySnapshot` plus the bound
  `ExecutionEnvironment`
- resolves the effective tool winner through the existing
  `RuntimeCapabilityContract`
- persists all candidate implementations for each projected logical tool and
  marks the snapshot winner as the default implementation

#### `ToolBindings::SelectImplementation`

- enforces the `reserved`, `whitelist_only`, and `replaceable` policy modes
- rejects overrides that violate the durable governance mode instead of relying
  on runtime-local convention

#### `ToolBindings::FreezeForTask`

- runs at `AgentTaskRun` creation
- reads the persisted turn snapshot plus the current profile policy to decide
  which logical tools are visible for this task boundary
- creates one binding row per visible governed tool

#### `ToolInvocations::Start` and `ToolInvocations::Complete`

- create and finish invocation rows against an existing frozen binding
- increment `attempt_no` per binding
- keep the invocation aligned with the same `AgentTaskRun`,
  `ToolDefinition`, and `ToolImplementation` that were frozen earlier

#### `ToolInvocations::Fail`

- marks one frozen invocation as terminal without introducing a separate
  source-specific audit path
- preserves the same task, definition, and implementation references chosen at
  bind time
- stores source-neutral failure metadata on the existing `ToolInvocation` row

#### `MCP::StreamableHttpTransport`

- implements the narrow Streamable HTTP MCP transport adopted in Phase 2
- opens one governed MCP session through:
  - `initialize`
  - `notifications/initialized`
  - one SSE readiness stream
  - later `tools/call` requests
- keeps transport handling outside controllers so the same client can be used
  from task-execution services and manual validation scripts

#### `MCP::InvokeTool`

- executes one MCP-backed governed tool through the same `ToolBinding` and
  `ToolInvocation` rows used by non-MCP governed tools
- persists durable MCP session state on `ToolBinding.binding_payload["mcp"]`
- records success through `ToolInvocations::Complete`
- records transport, protocol, and semantic failures through
  `ToolInvocations::Fail`
- clears the stored MCP session id after `session_not_found` so the next
  attempt reinitializes cleanly instead of reusing dead transport state

## Invariants

- provider governance rows stay installation-scoped and `global`; they are not
  user-private records
- governance models stay independent from YAML loading and only enforce SQL and
  structural invariants
- known provider handles are validated at the application write boundary against
  the config-backed catalog snapshot instead of inventing provider or model SQL
  entities
- catalog volatility stays in config; mutable installation facts stay in SQL
- audited mutations flow through explicit services rather than ad hoc model
  saves in controllers or later runtime code
- provider availability is derived from catalog visibility plus governance rows;
  no single SQL row overrides the catalog schema itself
- governed tool selection is frozen on `AgentTaskRun` boundaries, not recomputed
  on each invocation
- every agent-facing governed-tool identifier exposed through capability
  endpoints is a `public_id`, never an internal numeric key
- reserved `core_matrix__*` tool names are controlled at the snapshot boundary
  and cannot be claimed by agent-owned runtime payloads
- MCP session state is durable per frozen binding, not per transient client
  object
- MCP transport failure, protocol failure, and semantic tool failure all stay
  in the same invocation-history model

## Failure Modes

- unknown provider handles are invalid for credentials, entitlements, and
  policies
- incomplete throttling pairs are rejected
- rolling five-hour entitlements with the wrong `window_seconds` are rejected
- missing or malformed metadata or selection-default hashes are rejected
- availability checks can reject candidates as:
  - `unknown_provider`
  - `unknown_model`
  - `model_disabled`
  - `provider_disabled`
  - `environment_not_allowed`
  - `policy_disabled`
  - `missing_entitlement`
  - `missing_credential`
- capability-governance writes can reject invalid states as:
  - reserved runtime use of `core_matrix__*` names
  - non-default overrides for `reserved` definitions
  - non-default overrides for `whitelist_only` definitions
  - attempts to bind or invoke an implementation that does not match the
    frozen task projection
- governed MCP execution can fail as:
  - `transport` when the HTTP transport or stored session is unavailable
  - `protocol` when JSON-RPC or SSE payloads are malformed
  - `semantic` when the remote MCP tool returns an explicit tool error
- `session_not_found` is treated as a retryable transport failure and clears
  the persisted session id from the binding payload
