# Provider Catalog Config And Validation

## Purpose

Task 05.1 introduces the config-backed provider and model catalog that later
governance, selector resolution, and runtime execution work will read. This
task keeps provider and role catalog data in YAML instead of SQL and validates
that the catalog is structurally sound before later runtime code depends on it.

## Loader Behavior

- `ProviderCatalog::Load` reads `config/providers/catalog.yml`.
- The loader uses Rails `config_for` semantics, so the file can stay rooted
  under `shared:` while still allowing future environment overlays if they are
  ever needed.
- Missing catalog files raise `ProviderCatalog::Load::MissingCatalog`.
- Successful loads return a catalog object with provider lookup, model lookup,
  and ordered role-candidate lookup helpers.

## Catalog Shape

- the catalog is rooted at `providers` plus `model_roles`
- provider handles are stable config identifiers such as
  `codex_subscription` or `openai`
- model references stay provider-local, for example `gpt-5.4` or
  `gpt-5.3-chat-latest`
- role entries are ordered candidate lists in
  `provider_handle/model_ref` form

## Preserved Model Metadata

Each provider model preserves:

- display metadata such as `display_name`
- context-window metadata such as `context_window_tokens`
- output-limit metadata such as `max_output_tokens`
- free-form metadata hashes for provider or UI-facing details
- explicit capability flags, including multimodal input support

## Capability Validation

Each model must declare:

- `text_output`
- `tool_calls`
- `structured_output`
- `multimodal_inputs.image`
- `multimodal_inputs.audio`
- `multimodal_inputs.video`
- `multimodal_inputs.file`

Those multimodal input flags are explicit so later attachment and context
assembly work can gate projection by declared capability instead of guessing
from provider name or model family.

## Role Catalog Validation

- role names must be stable kernel-facing identifiers
- each role must contain at least one candidate
- each candidate must use `provider_handle/model_ref` form
- each candidate must point at a known provider and known model
- candidate order is preserved exactly as configured

## Invariants

- provider and role catalog data remain config-backed, not SQL-backed
- provider-qualified model identity stays explicit and auditable
- role fallback remains explicit and bounded to the configured ordered list
- validation happens before later governance or runtime code can rely on the
  catalog

## Failure Modes

- missing catalog file
- invalid provider handles, model refs, or role names
- non-hash metadata sections
- missing or non-boolean capability flags
- role entries that point at unknown provider/model candidates

## Reference Sanity Check

The retained conclusion from the OpenClaw provider-catalog reference is narrow:
keeping provider identity explicit and config-backed is a sane baseline.

Core Matrix intentionally differs by using one static YAML catalog with strict
boot-time validation instead of runtime plugin discovery. The retained rule is
the explicit provider-qualified identity shape, not the plugin architecture.
