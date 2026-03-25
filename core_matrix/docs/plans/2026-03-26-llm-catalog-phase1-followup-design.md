# LLM Catalog Phase 1 Follow-Up Design

## Purpose

Phase 1 already established the provider catalog as the config-backed source of
truth for provider-qualified model identity, role ordering, and non-secret
runtime metadata. This follow-up closes two gaps that surfaced during the
Phase 1 review:

- shipped models cannot currently be disabled through `config.d` deep-merge
  overrides
- model `request_defaults` do not formally support the sampling knobs needed by
  self-hosted and OSS OpenAI-compatible models

This design keeps the work inside the Phase 1 boundary. It extends the catalog
contract, validation, docs, samples, and selector-facing availability behavior.
It does not wire model request defaults into Phase 2 execution yet.

## Confirmed Scope

### In Scope

- add model-level `enabled`
- make `enabled` deep-merge friendly so a user override can disable a shipped
  model
- formally support these `request_defaults` keys:
  - `reasoning_effort`
  - `temperature`
  - `top_p`
  - `top_k`
  - `min_p`
  - `presence_penalty`
  - `repetition_penalty`
- validate those keys with basic type and broad range checks
- expose disabled models as unavailable and not UI-selectable
- keep role lists tolerant of disabled models by filtering them through normal
  availability checks

### Out of Scope

- wiring model `request_defaults` into the actual provider request payload
- defining the final precedence merge between model defaults, agent defaults,
  conversation overrides, and turn overrides
- provider-specific capability checks for whether a given model actually accepts
  the configured sampling knobs

## Existing Constraints

- `ProviderCatalog::Load` already deep-merges hashes and replaces arrays.
- The catalog does not support delete semantics through overrides.
- Provider visibility already uses `enabled: false` at the provider level.
- `Providers::CheckAvailability` is the selector-facing availability gate.
- `Workflows::ResolveModelSelector` already treats availability failures as:
  - explicit candidate hard failure
  - role-local fallback for ordered role candidates

Those constraints make model-level enablement a good fit for the existing
catalog and selector design.

## Decision 1: Add `models.*.enabled`

Each model definition gains one required boolean field:

```yaml
providers:
  openrouter:
    models:
      openai-gpt-5.4:
        enabled: true
```

### Semantics

- `enabled: true` means the model is catalog-visible and eligible for normal
  availability evaluation.
- `enabled: false` means the model remains present in the catalog definition
  but is not usable, not selectable, and not UI-visible.
- User overrides can disable a shipped model through deep merge:

```yaml
providers:
  openrouter:
    models:
      openai-gpt-5.4:
        enabled: false
```

### Why keep disabled models in the catalog?

- deep merge needs a stable key to target
- role definitions may still reference the model during override transitions
- explicit config remains auditable instead of introducing delete semantics

## Decision 2: Availability Uses `model_disabled`

`Providers::CheckAvailability` gains one new failure reason:

- `model_disabled`

Evaluation order becomes:

1. provider exists
2. model exists
3. model `enabled` is true
4. provider `enabled` is true
5. provider environment is allowed
6. installation policy is not disabled
7. entitlement exists
8. matching credential exists when required

### Selector Behavior

- explicit candidate selection against a disabled model fails immediately with
  `model_disabled`
- role-based selection silently skips the disabled model and continues to the
  next role candidate
- `model_roles` validation remains reference-only and does not reject disabled
  entries

This keeps role lists operationally tolerant while still making disabled models
unusable everywhere else.

## Decision 3: Keep Sampling Knobs Inside `request_defaults`

The new sampling knobs belong in the existing `request_defaults` hash instead
of becoming model-level top-level fields or a new `sampling_defaults` section.

```yaml
providers:
  local:
    models:
      qwen3-14b:
        enabled: true
        request_defaults:
          temperature: 1.0
          top_p: 0.95
          top_k: 20
          min_p: 0.0
          presence_penalty: 1.5
          repetition_penalty: 1.0
```

### Rationale

- `request_defaults` already exists for model-scoped request tuning
- `reasoning_effort` already lives there
- this avoids splitting request knobs across multiple sections
- future Phase 2 request assembly can treat model defaults as one input source

## Decision 4: Validate `request_defaults` as a Known Contract

Phase 1 should stop treating `request_defaults` as an unbounded hash. The
catalog should accept only known keys and validate them with broad, portable
checks.

### Supported Keys

- `reasoning_effort`: non-empty string
- `temperature`: numeric and `>= 0`
- `top_p`: numeric and between `0` and `1`
- `top_k`: integer and `>= 0`
- `min_p`: numeric and between `0` and `1`
- `presence_penalty`: numeric
- `repetition_penalty`: numeric and `> 0`

### Validation Philosophy

- validate type and broad shape only
- reject unknown keys so typos fail early
- do not encode provider-specific or model-specific compatibility rules
- do not guarantee the target provider will accept the final request

That final responsibility stays with the operator who configures the model.

## Decision 5: Keep Phase 1 and Phase 2 Separate

Phase 1 ends once the catalog can:

- declare model-level enablement
- declare validated request-default sampling knobs
- merge those values through `config.d`
- expose correct selector-facing availability behavior
- document the new contract clearly

Phase 2 will later define:

- how model `request_defaults` flow into actual provider requests
- how those defaults merge with agent defaults
- how conversation and turn overrides take precedence over model defaults

For this follow-up, model defaults are catalog state only. They are not yet
copied into `Turn.resolved_config_snapshot` or any provider execution path.

## Test Coverage Requirements

### Validator Coverage

- accept `enabled: true`
- accept `enabled: false`
- accept a disabled model that is still referenced from `model_roles`
- reject missing `enabled`
- reject non-boolean `enabled`
- accept all supported `request_defaults` keys together
- reject unknown `request_defaults` keys
- reject blank `reasoning_effort`
- reject invalid ranges or types for each supported numeric knob

### Loader Coverage

- deep-merge can disable a shipped model through `config.d`
- deep-merge combines nested `request_defaults` hashes instead of replacing the
  whole hash when only one knob is overridden
- environment-specific overrides still win last

### Availability And Selector Coverage

- availability returns `model_disabled`
- explicit candidate selection hard-fails on `model_disabled`
- role-based selection skips a disabled earlier candidate and resolves the next
  usable model

### Real Catalog Coverage

- the shipped catalog remains boot-loadable after every model gains `enabled`
- the shipped catalog preserves existing behavior when models stay enabled

## Documentation Updates

Update these local documents:

- `core_matrix/docs/behavior/provider-catalog-config-and-validation.md`
- `core_matrix/docs/behavior/provider-governance-models-and-services.md`
- `core_matrix/docs/behavior/workflow-model-selector-resolution.md`
- `core_matrix/docs/behavior/verification-and-manual-validation-baseline.md`
- `core_matrix/config.d/llm_catalog.yml.sample`

The sample override file should explicitly demonstrate:

- disabling one shipped model with `enabled: false`
- adding OSS sampling defaults under `request_defaults`

## Phase 2 Handoff

After the Phase 1 follow-up lands, the Phase 2 discussion should inherit these
facts:

- model `request_defaults` are now a validated catalog input
- model defaults are the lowest-priority request layer
- agent defaults, conversation overrides, and turn overrides are expected to
  override them later
- disabled models must remain hidden and unusable in any future UI or runtime
  selector surface
