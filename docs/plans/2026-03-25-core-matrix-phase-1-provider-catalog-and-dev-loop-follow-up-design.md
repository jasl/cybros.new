# Core Matrix Phase 1 Provider Catalog And Dev Loop Follow-Up Design

## Status

- approved on `2026-03-25`
- scope owner: `core_matrix`
- source: follow-up design for provider-catalog expansion, local-development
  provider support, and Docker-friendly configuration overrides

## Goal

Extend the Phase 1 provider-governance substrate so `core_matrix` can ship a
real default provider catalog, support installation-local overrides without
polluting git history, treat credential requirements as part of provider
availability, and provide a built-in development/test mock provider loop that
works after `db:seed`.

This follow-up is intentionally allowed to make breaking changes. The current
database is considered disposable, and the design should prefer a cleaner
orthogonal shape over compatibility layers around the first landed Phase 1
catalog schema.

## Alignment With Existing Core Matrix Design

This design keeps the Phase 1 architectural split from the kernel greenfield
design and the provider-governance behavior documents:

- the provider catalog remains config-backed
- mutable installation facts remain SQL-backed through
  `ProviderCredential`, `ProviderEntitlement`, and `ProviderPolicy`
- conversation selector behavior keeps `auto` and explicit candidate modes
- `auto` continues to mean "resolve through `role:main`"

What changes is the meaning of the config-backed catalog. It stops being a
minimal provider/model directory and becomes the non-secret runtime catalog for
provider connectivity, capability metadata, environment gating, and credential
requirements.

## Problem Statement

The current `core_matrix/config/providers/catalog.yml` schema is too narrow for
the provider surface the product now needs:

- it omits provider runtime metadata already present in the reference config,
  including `adapter_key`, `base_url`, `wire_api`, `transport`, and model-level
  `tokenizer_hint`
- it cannot describe development-only mock providers or default-disabled local
  self-hosted providers cleanly
- selector availability currently checks policy enablement and entitlement
  presence, but not credential availability
- the current config location is not ideal for Docker mounts because replacing
  the containing directory can hide the repository-shipped base config

## Design Decisions

### 1. Replace The Current Catalog Path And Schema

Move the provider catalog entry point from
`core_matrix/config/providers/catalog.yml` to
`core_matrix/config/llm_catalog.yml`.

The new file becomes the canonical repository-tracked base catalog. The root
shape is explicit and does not rely on a `shared:` wrapper:

- `version`
- `providers`
- `model_roles`

This is a breaking change by design. The new loader should not try to preserve
the old path or old field contract behind compatibility glue.

### 2. Add Docker-Friendly Override Files Under `config.d`

All local or deployment-specific overrides flow through
`core_matrix/config.d/`.

For the LLM catalog, support these files:

- `core_matrix/config/llm_catalog.yml`
- `core_matrix/config.d/llm_catalog.yml`
- `core_matrix/config.d/llm_catalog.<rails_env>.yml`

Load order is fixed:

1. `config/llm_catalog.yml`
2. `config.d/llm_catalog.yml`
3. `config.d/llm_catalog.<rails_env>.yml`

Merge rules are intentionally simple:

- hashes deep-merge
- arrays replace the earlier value entirely
- `providers`, `models`, and `model_roles` merge by stable key
- deletion is not supported in v1 follow-up; operators should use
  `enabled: false` instead

This keeps the repository-shipped base config present inside Docker images while
allowing operators to mount only `config.d`.

### 3. Expand The Catalog Into A Non-Secret Runtime Catalog

The catalog now owns all non-secret provider runtime metadata that later
execution, UI, or health surfaces may need.

Provider-level fields should support at least:

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
- `models`

Model-level fields should support at least:

- `display_name`
- `api_model`
- `tokenizer_hint`
- `context_window_tokens`
- `max_output_tokens`
- `context_soft_limit_ratio`
- `request_defaults`
- `metadata`
- `capabilities`

Capability validation should stay explicit and continue to require:

- `text_output`
- `tool_calls`
- `structured_output`
- `multimodal_inputs.image`
- `multimodal_inputs.audio`
- `multimodal_inputs.video`
- `multimodal_inputs.file`

The catalog still does not store secret material. API keys, OAuth tokens, and
similar credentials remain in `ProviderCredential`.

### 4. Keep Provider Availability Orthogonal

The follow-up should make provider availability a first-class application
concept instead of leaving pieces of the check scattered inside selector logic.

Use these four terms:

- `defined`: the provider/model exists in the loaded catalog
- `visible`: the provider is catalog-enabled and allowed in the current
  `Rails.env`
- `governed`: the installation has not disabled the provider through
  `ProviderPolicy.enabled = false`
- `usable`: the provider-qualified model can actually be selected for execution

A provider-qualified model is `usable` only when all of these are true:

- the provider is visible
- the provider is not disabled by installation policy
- the model exists in the catalog
- at least one active `ProviderEntitlement` exists for the provider
- if `requires_credential: true`, a matching
  `ProviderCredential(provider_handle, credential_kind)` exists

`codex_subscription` follows the same rule as other providers. Its only special
case is the credential kind, for example `oauth_codex` rather than `api_key`.

`ProviderPolicy` remains the installation-scoped dynamic override for temporary
provider shutdowns. The existing boolean `enabled` flag is sufficient for this
follow-up; no additional `disabled_reason` or `disabled_until` fields are
introduced.

### 5. Refactor Selector Resolution Around Availability

Conversation selector semantics remain unchanged at the user-facing level:

- `auto`
- explicit candidate

Execution semantics remain:

- `auto` normalizes to `role:main`
- explicit candidate normalizes to `candidate:provider_handle/model_ref`
- role-local fallback is allowed only within the selected role's ordered
  candidate list
- explicit candidate selection never falls back

What changes is how candidates are filtered. Selector resolution should depend
on one provider-availability service instead of reimplementing policy,
credential, entitlement, and environment checks inline.

Unavailable candidates should produce structured reasons suitable for later UI,
logging, and operational diagnostics, including at least:

- provider disabled by catalog
- provider not allowed in current environment
- provider disabled by policy
- missing entitlement
- missing credential
- unknown provider or model

### 6. Ship A Richer Default Provider Baseline

The repository-tracked base catalog should include these provider families:

- `codex_subscription`
  - enabled by default
  - requires credential
  - credential kind is OAuth-based
- `openai`
  - enabled by default
  - requires API-key credential
- `openrouter`
  - enabled by default
  - requires API-key credential
- `dev`
  - enabled by default only in `development` and `test`
  - requires no credential
  - points at the local mock LLM controller namespace inside the same Rails app
- `ollama`
  - present but disabled by default
  - serves as a local self-hosted example
- `llama_cpp`
  - present but disabled by default
  - serves as a local self-hosted example

This split keeps two local-development stories distinct:

- `dev` is the built-in deterministic development/test loop
- `ollama` and `llama_cpp` are operator-enabled examples for real local model
  backends

### 7. Bring `mock_llm` Into `core_matrix` As A Development/Test Surface

Copy the reference `mock_llm` controller implementation into `core_matrix` and
adapt it rather than rewriting it from scratch.

The retained behavior should include:

- `/mock_llm/v1/chat/completions`
- `/mock_llm/v1/models`
- deterministic markdown responses via `!md`
- delay controls via bare numeric prompts and `!mock slow=...`
- error simulation via `!mock error=...`
- streaming SSE responses
- optional usage blocks in stream mode

The route surface should be mounted only in `development` and `test`.

The `models` endpoint should not hardcode a separate model list. It should read
the currently loaded `dev` provider models from the catalog so the mock surface
and catalog stay aligned.

### 8. Use Seeds To Make Development And Manual Testing Smooth

The follow-up should extend `core_matrix/db/seeds.rb` so development and reset
flows produce a usable provider baseline without requiring hand edits.

Seed behavior should remain idempotent and should:

- keep the existing bundled runtime reconciliation
- ensure the `dev` provider has the installation-scoped governance rows it
  needs to be usable after `db:seed`
- read optional real-provider credentials from environment variables such as
  `OPENAI_API_KEY` and `OPENROUTER_API_KEY`
- upsert matching `ProviderCredential` rows when those environment variables are
  present
- ensure real providers with supplied credentials can become immediately usable
  by also seeding the minimal policy and entitlement rows they need

The design intentionally does not introduce a second installation-level default
model mechanism. Manual testing convenience should come from keeping
`Conversation` selector mode on `auto` and ensuring `role:main` resolves to a
usable candidate after `db:seed`.

### 9. Verification Expectations

The implementation plan should cover at least:

- loader tests for base catalog plus `config.d` override precedence
- validator tests for the expanded provider and model schema
- availability-service tests for missing credential, missing entitlement,
  policy-disabled, and environment-gated candidates
- selector-resolution tests proving fallback remains role-local
- request or integration coverage for the `mock_llm` controllers
- seed tests proving idempotent creation of development and real-provider
  governance rows

The standard `core_matrix` verification suite remains the final close-out gate.

## Reference Capture

This design consulted repository references and retains these conclusions
locally:

- `references/original/cybros/config/llm/providers.yml` is useful as a source
  of provider-runtime metadata that the current `core_matrix` catalog omitted,
  especially `tokenizer_hint`, transport metadata, credential requirements, and
  development or self-hosted provider examples
- `references/original/cybros/app/controllers/mock_llm` contains practical
  development and UI-test behavior worth preserving, especially deterministic
  markdown, numeric delay shortcuts, error simulation, and streaming responses
- `references/original/cybros/db/seeds.rb` confirms that development
  convenience improves materially when optional real-provider credentials from
  environment variables are seeded into the app's provider-governance layer

Core Matrix intentionally differs from the reference application in two ways:

- it keeps the provider-governance split defined by the greenfield design, so
  secret-bearing credentials remain SQL-backed while the catalog remains
  config-backed
- it adopts a Docker-friendly `config.d` override convention instead of asking
  operators to replace the base catalog file or its containing directory

## Open Implementation Boundary

This document approves a new Phase 1 follow-up plan. The next document should
turn these decisions into an implementation plan with small, test-first tasks,
explicit file lists, and commit checkpoints.
