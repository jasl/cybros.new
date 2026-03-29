# Provider Catalog Config And Validation

## Purpose

The provider catalog remains the config-backed source of truth for
provider-qualified model identity, role ordering, and non-secret runtime
metadata that later governance, selector resolution, and runtime execution
depend on.

This document reflects the Phase 1 follow-up that widened the catalog from a
minimal directory into the shipped non-secret runtime catalog.

## Loader Behavior

- `ProviderCatalog::Load` reads `config/llm_catalog.yml`.
- The loader optionally overlays:
  - `config.d/llm_catalog.yml`
  - `config.d/llm_catalog.<rails_env>.yml`
- Load order is fixed:
  1. base catalog
  2. shared override file
  3. environment-specific override file
- Missing base catalog files raise `ProviderCatalog::Load::MissingCatalog`.
- Successful loads return a catalog object with provider lookup, model lookup,
  and ordered role-candidate lookup helpers.

## Registry Behavior

- `ProviderCatalog::Registry.current` is the ordinary runtime entry point for
  static catalog reads.
- `ProviderCatalog::Registry` keeps one immutable snapshot per process and uses
  `ProviderCatalog::Load` only when it needs to build or refresh that snapshot.
- `ProviderCatalog::Registry.reload!` reloads the current process immediately,
  then publishes the new revision to shared cache when available.
- `ProviderCatalog::Registry.ensure_fresh!` gives other processes eventual
  consistency by reloading after they observe a changed shared revision.
- `ProviderCatalog::EffectiveCatalog` builds installation-scoped availability,
  selector resolution, and UI-facing selector option helpers on top of the
  current registry snapshot.
- Ordinary application code should depend on `Registry` or `EffectiveCatalog`,
  not call `Load` directly.

## Write-Boundary Behavior

- Provider catalog membership is not enforced by governance models themselves.
- `ProviderCredentials::UpsertSecret`,
  `ProviderEntitlements::Upsert`,
  `ProviderPolicies::Upsert`, and
  `Conversations::UpdateOverride`
  are the application write boundaries that validate provider and model
  references against the current catalog snapshot.
- This keeps YAML parsing and reload sensitivity out of ordinary Active Record
  model validation while preserving catalog-backed invariants at supported write
  entry points.

## Merge Rules

- hashes deep-merge
- arrays replace earlier values entirely
- provider, model, and role entries merge by their stable keys
- deletion is not supported through overrides; disabling a shipped provider
  should use `enabled: false`
- disabling a shipped model should use `models.<model_ref>.enabled: false`
- role lists may still reference disabled models; availability filtering skips
  them at selection time instead of forcing delete-like catalog edits

This shape keeps the repository-tracked base catalog inside Docker images while
allowing operators to mount only `config.d`.

## Catalog Shape

The catalog root contains:

- `version`
- `providers`
- `model_roles`

Provider handles remain stable config identifiers such as `openai`,
`codex_subscription`, or `openrouter`.

Model references remain provider-local identifiers such as
`gpt-5.3-chat-latest`, `openai-gpt-5.4`, `anthropic-claude-opus-4.6-nitro`, or
`mock-model`.

Role entries remain ordered candidate lists in `provider_handle/model_ref`
form.

## Preserved Provider Metadata

Each provider preserves non-secret runtime metadata including:

- `display_name`
- `enabled`
- `environments`
- `adapter_key`
- `base_url`
- `headers`
- `wire_api`
- `transport`
- `responses_path`
- `requires_credential`
- `credential_kind`
- `metadata`

This metadata remains config-backed. Secret-bearing values such as API keys and
OAuth tokens remain in `ProviderCredential`.

## Preserved Model Metadata

Each provider model preserves:

- `enabled`
- `display_name`
- `api_model`
- `tokenizer_hint`
- `context_window_tokens`
- `max_output_tokens`
- `context_soft_limit_ratio`
- `request_defaults`
- `metadata`
- explicit capability flags, including multimodal input support

Model `enabled` defaults to `true` when omitted. Catalog authors only need to
declare it explicitly when disabling a model or when they want that boolean to
remain fully explicit in local overrides.

`request_defaults` remains model-scoped catalog state in Phase 1. Phase 2 now
wires those values into provider-backed request execution.

For provider execution, merge precedence is:

1. model catalog `request_defaults`
2. the turn's effective resolved config snapshot

The turn snapshot is already the resolved execution-config boundary after agent,
conversation, and turn-level config resolution, so provider execution does not
re-open older config layers directly. Provider request execution also filters
these settings by the current wire API so non-provider config keys do not leak
into outbound requests.

Supported `request_defaults` keys are:

- `reasoning_effort`
- `temperature`
- `top_p`
- `top_k`
- `min_p`
- `presence_penalty`
- `repetition_penalty`

`ProviderRequestSettingsSchema` is now the single contract object that owns
that wire-API-specific allowlist and value validation. Catalog validation,
execution-snapshot assembly, and provider request-context building all ask the
same schema object rather than each carrying their own copy of the key table.

`ProviderRequestContext` is the canonical runtime contract that carries the
filtered provider request settings, hard limits, advisory hints, and provider
metadata into provider execution.

## Capability Validation

Each model must declare:

- `text_output`
- `tool_calls`
- `structured_output`
- `multimodal_inputs.image`
- `multimodal_inputs.audio`
- `multimodal_inputs.video`
- `multimodal_inputs.file`

Those multimodal input flags stay explicit so later attachment and context
assembly work can gate projection by declared capability instead of guessing
from provider or model family.

## Validation Rules

- the catalog `version` must be a supported integer
- provider handles, model refs, and role names must match the catalog formats
- providers must declare required runtime fields including enablement,
  environment gating, transport metadata, and credential metadata
- models must declare `api_model` and `tokenizer_hint` in addition to context,
  output, metadata, and capability fields
- omitted model `enabled` normalizes to `true`
- explicit model `enabled` values must be boolean
- `request_defaults` must be a hash that uses only supported keys
- supported request-setting keys are validated against the current wire API
  through `ProviderRequestSettingsSchema`
- `request_defaults` values must pass broad type and value-range checks:
  - `reasoning_effort` must be a non-empty string
  - `temperature` must be numeric and `>= 0`
  - `top_p` and `min_p` must be numeric and between `0` and `1` inclusive
  - `top_k` must be an integer and `>= 0`
  - `presence_penalty` must be numeric
  - `repetition_penalty` must be numeric and `> 0`
- role catalogs must contain at least one candidate, preserve ordering, and
  point only at known provider-qualified models

## Shipped Baseline

The repository-tracked base catalog ships provider families for:

- `codex_subscription`
- `openai`
- `openrouter`
- `dev`
- `local`

`dev` is enabled only in `development` and `test` and remains dedicated to the
shipped `mock_llm` development loop.

`local` remains present but disabled by default as the single shipped example
for real self-hosted OpenAI-compatible inference services such as vLLM,
Ollama, or llama.cpp running in OpenAI-compatible mode.

`role:main` and the other real workload roles intentionally exclude the shipped
mock provider. The catalog instead ships `role:mock` so development and manual
testing can opt into `dev/mock-model` without changing the semantics of
production-facing auto selection.

## Invariants

- provider and role catalog data remain config-backed, not SQL-backed
- provider-qualified model identity stays explicit and auditable
- role fallback remains explicit and bounded to the configured ordered list
- validation happens before later governance or runtime code can rely on the
  catalog
- credential requirements are declared in config, while actual credentials stay
  installation-scoped in SQL

## Failure Modes

- missing base catalog file
- unsupported or missing catalog version
- invalid provider handles, model refs, or role names
- non-hash headers, metadata, or request-default sections
- non-boolean model `enabled` flags
- unsupported request-default keys
- invalid request-default types or broad ranges
- missing or non-boolean capability flags
- missing provider runtime fields or model tokenizer metadata
- role entries that point at unknown provider/model candidates
