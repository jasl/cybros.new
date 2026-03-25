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

## Merge Rules

- hashes deep-merge
- arrays replace earlier values entirely
- provider, model, and role entries merge by their stable keys
- deletion is not supported through overrides; disabling a shipped provider
  should use `enabled: false`

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

- `display_name`
- `api_model`
- `tokenizer_hint`
- `context_window_tokens`
- `max_output_tokens`
- `context_soft_limit_ratio`
- `request_defaults`
- `metadata`
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
- missing or non-boolean capability flags
- missing provider runtime fields or model tokenizer metadata
- role entries that point at unknown provider/model candidates
