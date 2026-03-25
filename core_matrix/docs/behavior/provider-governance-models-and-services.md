# Provider Governance Models And Services

## Purpose

Provider governance rows remain the installation-scoped SQL layer that sits on
top of the config-backed provider catalog. They store mutable installation
facts only: credentials, entitlements, and policies.

The catalog declares whether a provider requires credentials and which
credential kind it expects. Governance rows answer whether this installation
currently satisfies those declared requirements.

## Aggregate Responsibilities

### ProviderCredential

- `ProviderCredential` stores secret connection material for one provider handle
  and credential kind inside one installation.
- Secret material is encrypted at rest with Rails Active Record Encryption.
- Credential rows track rotation time separately from general metadata.
- One installation cannot hold duplicate rows for the same
  `provider_handle + credential_kind` pair.

### ProviderEntitlement

- `ProviderEntitlement` stores subscription or quota facts for one provider
  handle inside one installation.
- Entitlements are keyed so one provider can hold more than one tracked
  entitlement shape over time.
- The current baseline supports explicit window kinds including
  `rolling_five_hours`.
- Rolling five-hour entitlements persist their derived `window_seconds`
  explicitly as `18_000`.

### ProviderPolicy

- `ProviderPolicy` stores enablement, concurrency, throttling, and provider-side
  selection defaults for one provider handle inside one installation.
- One installation keeps at most one policy row per provider handle.
- `enabled = false` is the installation-scoped dynamic override for temporarily
  disabling an otherwise catalog-visible provider.
- Throttling remains explicit through paired limit and period fields instead of
  hidden rate-limit heuristics.

## Services

### `ProviderCredentials::UpsertSecret`

- Upserts one `ProviderCredential` by installation, provider handle, and
  credential kind.
- Rotates the encrypted secret and `last_rotated_at` timestamp together.
- Writes `provider_credential.upserted` audit rows without storing plaintext
  secret material in audit metadata.

### `ProviderEntitlements::Upsert`

- Upserts one `ProviderEntitlement` by installation, provider handle, and
  entitlement key.
- Derives `window_seconds` from the declared `window_kind`.
- Writes `provider_entitlement.upserted` audit rows.

### `ProviderPolicies::Upsert`

- Upserts one `ProviderPolicy` by installation and provider handle.
- Persists provider enablement, concurrency, throttling, and selection-default
  settings through one audited boundary.
- Writes `provider_policy.upserted` audit rows.

### `Providers::CheckAvailability`

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

## Invariants

- provider governance rows stay installation-scoped and `global`; they are not
  user-private records
- governance rows validate against known provider handles from the config-backed
  catalog instead of inventing provider or model SQL entities
- catalog volatility stays in config; mutable installation facts stay in SQL
- audited mutations flow through explicit services rather than ad hoc model
  saves in controllers or later runtime code
- provider availability is derived from catalog visibility plus governance rows;
  no single SQL row overrides the catalog schema itself

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
