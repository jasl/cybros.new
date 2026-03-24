# Provider Governance Models And Services

## Purpose

Task 05.2 adds the installation-scoped provider governance records that sit on
top of the config-backed provider catalog from Task 05.1. These rows store
mutable installation facts only: credentials, entitlements, and policies.

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

## Invariants

- provider governance rows stay installation-scoped and `global`; they are not
  user-private records
- governance rows validate against known provider handles from the config-backed
  catalog instead of inventing provider or model SQL entities
- catalog volatility stays in config; mutable installation facts stay in SQL
- audited mutations flow through explicit services rather than ad hoc model
  saves in controllers or later runtime code

## Failure Modes

- unknown provider handles are invalid for credentials, entitlements, and
  policies
- incomplete throttling pairs are rejected
- rolling five-hour entitlements with the wrong `window_seconds` are rejected
- missing or malformed metadata or selection-default hashes are rejected

## Reference Sanity Check

The retained conclusion from the Dify and OpenClaw reference slices is
structural, not implementation-specific:

- provider catalog metadata and provider configuration state should stay
  separated
- secret-bearing credentials should not collapse into the same structure as
  volatile provider/model catalog data

Core Matrix intentionally keeps that separation with installation-scoped SQL
governance rows plus a separate config-backed catalog, instead of adopting
Dify's tenant-provider response shapes or OpenClaw's environment-secret
resolution flow directly.
