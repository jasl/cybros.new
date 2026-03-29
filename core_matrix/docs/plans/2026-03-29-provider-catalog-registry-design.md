# Provider Catalog Registry Design

**Date:** 2026-03-29

**Goal:** Centralize static LLM catalog loading behind a single registry, support safe reloads, and move catalog-dependent validation out of Active Record models and into application services.

## Scope

This design covers:

- loading `config/llm_catalog.yml`
- merging `config.d/llm_catalog.yml` and `config.d/llm_catalog.<env>.yml`
- holding the validated static catalog in process memory
- supporting manual reload for future admin-triggered hot reload flows
- providing a formal extension point for installation-scoped availability logic

This design does not add database-backed `model_roles` overrides yet.

## Architecture

### `ProviderCatalog::Snapshot`

An immutable object representing one validated static catalog snapshot.

Responsibilities:

- expose read APIs such as `provider`, `model`, and `role_candidates`
- carry a deterministic `revision`
- hold the normalized provider/model/role data used by the rest of the app

### `ProviderCatalog::Registry`

The single runtime entry point for the static catalog.

Responsibilities:

- lazily load the current snapshot
- expose `current`, `reload!`, `revision`, and `ensure_fresh!`
- guarantee thread-safe in-process replacement of the current snapshot
- optionally publish a shared revision token through `Rails.cache`
- reload locally when another process has already published a newer revision

The registry stores the authoritative snapshot in process memory. `Rails.cache` is used only as a lightweight revision signal, not as the primary source of catalog data.

### `ProviderCatalog::EffectiveCatalog`

A facade for installation-scoped availability decisions.

Responsibilities:

- start from `ProviderCatalog::Registry.current`
- incorporate installation-scoped governance data such as `ProviderCredential`, `ProviderPolicy`, and `ProviderEntitlement`
- answer questions about what is actually usable for a given installation

This layer exists now as the formal extension point for future database-backed runtime overrides, including possible `model_roles` overrides.

## Reload Semantics

- `reload!` rebuilds the static snapshot from disk and replaces the in-process snapshot atomically.
- reload failure leaves the previous in-process snapshot untouched.
- the registry may publish the new revision to `Rails.cache`.
- other processes are only required to become consistent eventually.
- different processes observing different revisions during the reload window is acceptable.

## Validation Boundary

Static catalog existence checks should not run inside Active Record models.

This round moves catalog-backed validation to the application services that already own those writes:

- `ProviderCredentials::UpsertSecret`
- `ProviderPolicies::Upsert`
- `ProviderEntitlements::Upsert`
- `Conversations::UpdateOverride`

Models keep structural and relational validation only.

## Testing Strategy

This work needs focused tests for:

- snapshot loading and deterministic revision generation
- registry reload success and failure behavior
- registry thread safety during concurrent reads and reloads
- registry eventual consistency via shared revision signaling
- service-boundary validation for unknown providers and models

