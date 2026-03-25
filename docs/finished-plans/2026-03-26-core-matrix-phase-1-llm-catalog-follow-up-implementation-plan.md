# Core Matrix Phase 1 LLM Catalog Follow-Up Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Backfill the Phase 1 provider catalog so users can disable shipped models through `config.d` overrides and declare validated model sampling defaults without wiring those defaults into Phase 2 execution yet.

**Architecture:** Extend the catalog contract at the model layer, keep `enabled` and `request_defaults` inside the existing loader and validator flow, and route model disablement through `Providers::CheckAvailability` so selectors inherit the right semantics automatically. Keep the execution boundary unchanged: Phase 1 stores and validates the new fields, but does not merge them into runtime request payloads yet.

**Tech Stack:** Ruby on Rails, Minitest, YAML configuration, ActiveSupport configuration loading, project-local behavior docs

---

### Task 1: Tighten validator tests around `model.enabled` and `request_defaults`

**Files:**
- Modify: `core_matrix/test/services/provider_catalog/validate_test.rb`
- Modify: `core_matrix/app/services/provider_catalog/validate.rb`

**Step 1: Write failing validator tests**

Add focused tests for:

- defaulting omitted `enabled` to `true`
- accepting `enabled: false` on a model
- accepting a disabled model that is still referenced from `model_roles`
- rejecting a model with non-boolean `enabled`
- accepting all supported `request_defaults` keys together
- rejecting an unknown `request_defaults` key such as `temprature`
- rejecting `reasoning_effort: ""`
- rejecting invalid values for:
  - `temperature: -0.1`
  - `top_p: -0.1`
  - `top_p: 1.1`
  - `top_k: 1.5`
  - `top_k: -1`
  - `min_p: -0.1`
  - `presence_penalty: "high"`
  - `repetition_penalty: 0`

Start the file with:

```ruby
class ProviderCatalog::ValidateTest < ActiveSupport::TestCase
  self.uses_real_provider_catalog = true
```

Add one happy-path example like:

```ruby
test "accepts model enabled false and supported request defaults" do
  catalog = ProviderCatalog::Validate.call(
    version: 1,
    providers: {
      "openai" => valid_provider_definition(
        models: {
          "gpt-5.3-chat-latest" => valid_model_definition(
            enabled: false,
            request_defaults: {
              reasoning_effort: "medium",
              temperature: 1.0,
              top_p: 0.95,
              top_k: 20,
              min_p: 0.0,
              presence_penalty: 1.5,
              repetition_penalty: 1.0,
            }
          ),
        }
      ),
    },
    model_roles: { "main" => ["openai/gpt-5.3-chat-latest"] }
  )

  refute catalog.fetch(:providers).fetch("openai").fetch(:models).fetch("gpt-5.3-chat-latest").fetch(:enabled)
end
```

**Step 2: Run the validator tests to confirm failure**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test test/services/provider_catalog/validate_test.rb
```

Expected:

- failures because omitted `enabled` still errors instead of defaulting to true
- failures because unsupported `request_defaults` keys are not yet checked
- failures because invalid numeric ranges still pass or produce the wrong error

**Step 3: Implement the validator changes**

Add `enabled` to normalized model output with a default of `true` when omitted,
and introduce a dedicated `validate_request_defaults` helper. Keep the checks
broad and portable:

```ruby
normalized[model_ref] = {
  enabled: validate_model_enabled(model_definition["enabled"], "#{provider_handle}/#{model_ref} enabled"),
  display_name: validate_string!(model_definition["display_name"], "#{provider_handle}/#{model_ref} display_name"),
  # ...
  request_defaults: validate_request_defaults(provider_handle, model_ref, model_definition["request_defaults"]),
}
```

Use a helper shaped like:

```ruby
SUPPORTED_REQUEST_DEFAULTS = {
  "reasoning_effort" => :string,
  "temperature" => :non_negative_number,
  "top_p" => :probability,
  "top_k" => :non_negative_integer,
  "min_p" => :probability,
  "presence_penalty" => :number,
  "repetition_penalty" => :positive_number,
}.freeze
```

Reject unknown keys explicitly:

```ruby
unknown_keys = request_defaults.keys - SUPPORTED_REQUEST_DEFAULTS.keys
raise InvalidCatalog, "#{provider_handle}/#{model_ref} request_defaults contains unsupported keys: #{unknown_keys.join(", ")}" if unknown_keys.any?
```

Do not change `validate_model_roles` to reject disabled models. Role entries
must remain reference-valid even when availability later filters them out.

**Step 4: Run the validator tests to confirm they pass**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test test/services/provider_catalog/validate_test.rb
```

Expected:

- validator tests pass

**Step 5: Commit**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
git add core_matrix/test/services/provider_catalog/validate_test.rb core_matrix/app/services/provider_catalog/validate.rb
git commit -m "test: tighten llm catalog model validation"
```

### Task 2: Bring the shared test catalog and shipped catalog up to the new model contract

**Files:**
- Modify: `core_matrix/test/test_helper.rb`
- Modify: `core_matrix/config/llm_catalog.yml`
- Modify: `core_matrix/test/integration/provider_catalog_boot_flow_test.rb`
- Modify: `core_matrix/test/services/provider_catalog/load_test.rb`

**Step 1: Write one real-catalog smoke assertion for model enablement**

Extend the boot-flow test so it checks a known shipped model exposes
`enabled: true`:

```ruby
test "the shipped provider catalog is boot-loadable" do
  catalog = ProviderCatalog::Load.call

  assert catalog.providers.present?
  assert catalog.model_roles.present?
  assert_equal true, catalog.model("openai", "gpt-5.4").fetch(:enabled)
end
```

**Step 2: Run the real-catalog smoke to confirm failure**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test test/integration/provider_catalog_boot_flow_test.rb
```

Expected:

- failure because shipped models still require explicit `enabled` instead of
  defaulting omitted values to true

**Step 3: Update the shipped and test catalogs**

Remove redundant `enabled: true` entries from shipped models in
`config/llm_catalog.yml`. Keep the new sampling knobs unset by default unless a
model already has a legitimate existing default such as `reasoning_effort`.

Update `test/test_helper.rb` so every stubbed model also carries
`enabled: true` by default:

```ruby
def test_model_definition(display_name:, api_model:, tokenizer_hint:, context_window_tokens:, max_output_tokens:, enabled: true, context_soft_limit_ratio: 0.8, request_defaults: {}, metadata: {}, capabilities: nil, multimodal_inputs: nil)
  {
    enabled: enabled,
    display_name: display_name,
    api_model: api_model,
    # ...
  }
end
```

Also update `test/services/provider_catalog/load_test.rb` fixture YAML so the
temporary catalog written in the test includes explicit model `enabled` values.

**Step 4: Run the real-catalog and loader tests**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test test/integration/provider_catalog_boot_flow_test.rb test/services/provider_catalog/load_test.rb
```

Expected:

- both tests pass
- the temporary catalog fixtures remain valid under the stricter contract

**Step 5: Commit**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
git add core_matrix/test/test_helper.rb core_matrix/config/llm_catalog.yml core_matrix/test/integration/provider_catalog_boot_flow_test.rb core_matrix/test/services/provider_catalog/load_test.rb
git commit -m "chore: add model enabled to shipped catalogs"
```

### Task 3: Lock deep-merge behavior for disabled models and nested request defaults

**Files:**
- Modify: `core_matrix/test/services/provider_catalog/load_test.rb`
- Modify: `core_matrix/app/services/provider_catalog/load.rb` only if the new tests expose a real merge bug

**Step 1: Write failing merge tests**

Add one temporary-catalog test that proves a `config.d` override can disable a
shipped model and deep-merge nested `request_defaults`:

```ruby
File.write(File.join(dir, "config", "llm_catalog.yml"), <<~YAML)
  version: 1
  providers:
    openai:
      # ...
      models:
        gpt-5.4:
          enabled: true
          display_name: GPT-5.4
          # ...
          request_defaults:
            reasoning_effort: high
YAML

File.write(File.join(dir, "config.d", "llm_catalog.yml"), <<~YAML)
  providers:
    openai:
      models:
        gpt-5.4:
          enabled: false
          request_defaults:
            temperature: 1.0
            top_p: 0.95
YAML
```

Assert:

```ruby
model = catalog.model("openai", "gpt-5.4")
assert_equal false, model.fetch(:enabled)
assert_equal(
  { reasoning_effort: "high", temperature: 1.0, top_p: 0.95 }.deep_stringify_keys,
  model.fetch(:request_defaults)
)
```

Add one more environment-specific override proving last-write-wins still holds
for nested keys such as `temperature`.

**Step 2: Run the loader tests**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test test/services/provider_catalog/load_test.rb
```

Expected:

- either the new tests already pass because the existing deep merge is correct
- or a focused failure points at a nested-merge regression

**Step 3: Keep or fix the loader**

If the tests pass, do not modify `app/services/provider_catalog/load.rb`.

If they fail, fix only the merge bug and keep the rules unchanged:

- hashes deep-merge
- arrays replace
- no delete semantics

**Step 4: Run the loader tests again**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test test/services/provider_catalog/load_test.rb
```

Expected:

- loader tests pass with the new deep-merge coverage in place

**Step 5: Commit**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
git add core_matrix/test/services/provider_catalog/load_test.rb core_matrix/app/services/provider_catalog/load.rb
git commit -m "test: lock llm catalog merge behavior"
```

### Task 4: Add `model_disabled` availability and selector coverage

**Files:**
- Modify: `core_matrix/test/services/providers/check_availability_test.rb`
- Modify: `core_matrix/test/services/workflows/resolve_model_selector_test.rb`
- Modify: `core_matrix/app/services/providers/check_availability.rb`

**Step 1: Write failing availability and selector tests**

In `check_availability_test.rb`, add:

```ruby
test "returns model disabled when the model exists but is disabled" do
  installation = create_installation!
  create_provider_entitlement!(installation: installation, provider_handle: "openrouter")
  create_provider_credential!(installation: installation, provider_handle: "openrouter", credential_kind: "api_key")

  disabled_catalog = build_catalog_with_disabled_model("openrouter", "openai-gpt-5.4")

  result = Providers::CheckAvailability.call(
    installation: installation,
    provider_handle: "openrouter",
    model_ref: "openai-gpt-5.4",
    env: "test",
    catalog: disabled_catalog
  )

  assert_equal false, result.usable?
  assert_equal "model_disabled", result.reason_key
end
```

In `resolve_model_selector_test.rb`, add both:

- one explicit candidate test that fails with `model_disabled`
- one role test that disables the first `role:main` candidate and confirms
  selection falls through to the next candidate with `fallback_count == 1`

Use `with_stubbed_provider_catalog(build_test_provider_catalog_from(...))` or a
similar local helper so the test can mutate the catalog without rewriting
global fixtures.

**Step 2: Run the targeted tests to confirm failure**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test test/services/providers/check_availability_test.rb test/services/workflows/resolve_model_selector_test.rb
```

Expected:

- `CheckAvailability` still treats disabled models as usable or unknown
- explicit candidate and role-fallback tests fail until availability adds the
  new reason

**Step 3: Implement `model_disabled` in availability**

Add one guard immediately after model lookup:

```ruby
model = provider.fetch(:models)[@model_ref]
return unavailable("unknown_model") if model.blank?
return unavailable("model_disabled") unless model.fetch(:enabled)
return unavailable("provider_disabled") unless provider.fetch(:enabled)
```

Do not add selector-specific branching. `Workflows::ResolveModelSelector`
should continue to inherit behavior from availability:

- explicit candidate path hard-fails
- role path falls through under the existing filter behavior

**Step 4: Run the targeted tests again**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test test/services/providers/check_availability_test.rb test/services/workflows/resolve_model_selector_test.rb
```

Expected:

- availability returns `model_disabled`
- explicit candidate fails with `model_disabled`
- role resolution skips the disabled first candidate and resolves the next one

**Step 5: Commit**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
git add core_matrix/test/services/providers/check_availability_test.rb core_matrix/test/services/workflows/resolve_model_selector_test.rb core_matrix/app/services/providers/check_availability.rb
git commit -m "feat: disable llm catalog models through availability"
```

### Task 5: Update operator docs and the override sample

**Files:**
- Modify: `core_matrix/config.d/llm_catalog.yml.sample`
- Modify: `core_matrix/docs/behavior/provider-catalog-config-and-validation.md`
- Modify: `core_matrix/docs/behavior/provider-governance-models-and-services.md`
- Modify: `core_matrix/docs/behavior/workflow-model-selector-resolution.md`
- Modify: `core_matrix/docs/behavior/verification-and-manual-validation-baseline.md`

**Step 1: Update the sample override file**

Show both supported override patterns:

- disable one shipped model with `enabled: false`
- tune one OSS model through `request_defaults`

For example:

```yaml
providers:
  openrouter:
    models:
      openai-gpt-5.4-pro:
        enabled: false

  local:
    models:
      qwen3-32b:
        enabled: true
        request_defaults:
          temperature: 1.0
          top_p: 0.95
          top_k: 20
          min_p: 0.0
          presence_penalty: 1.5
          repetition_penalty: 1.0
```

Delete the obsolete note that says model-level disable is unsupported.

**Step 2: Update the behavior docs**

Record the new contract precisely:

- `provider-catalog-config-and-validation.md`
  - models now preserve `enabled`
  - `request_defaults` accepts only the supported keys
  - failure modes now include unsupported request-default keys and invalid
    request-default values
- `provider-governance-models-and-services.md`
  - `Providers::CheckAvailability` now returns `model_disabled`
- `workflow-model-selector-resolution.md`
  - explicit candidate disabled-model failure
  - role-local skip behavior for disabled models
- `verification-and-manual-validation-baseline.md`
  - manual selector validation now covers a disabled model in both explicit and
    role-based selection paths

**Step 3: Sanity-read the docs for Phase 1 / Phase 2 separation**

Make sure every doc says or implies:

- model defaults are stored and validated in Phase 1
- actual provider request merge precedence is deferred to Phase 2

**Step 4: Commit**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
git add core_matrix/config.d/llm_catalog.yml.sample core_matrix/docs/behavior/provider-catalog-config-and-validation.md core_matrix/docs/behavior/provider-governance-models-and-services.md core_matrix/docs/behavior/workflow-model-selector-resolution.md core_matrix/docs/behavior/verification-and-manual-validation-baseline.md
git commit -m "docs: describe llm catalog phase1 follow-up"
```

### Task 6: Run the final verification suite and close the Phase 1 loop

**Files:**
- Verify only; no new code unless verification exposes a real defect

**Step 1: Run the full targeted test suite**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test \
  test/services/provider_catalog/validate_test.rb \
  test/services/provider_catalog/load_test.rb \
  test/services/providers/check_availability_test.rb \
  test/services/workflows/resolve_model_selector_test.rb \
  test/integration/provider_catalog_boot_flow_test.rb \
  test/integration/seed_baseline_test.rb
```

Expected:

- all provider-catalog and selector tests pass
- the real catalog still boots
- the seed baseline still preserves `role:mock` and `role:main` semantics

**Step 2: Run targeted lint on touched Ruby files**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rubocop app/services/provider_catalog/validate.rb app/services/providers/check_availability.rb test/services/provider_catalog/validate_test.rb test/services/provider_catalog/load_test.rb test/services/providers/check_availability_test.rb test/services/workflows/resolve_model_selector_test.rb test/test_helper.rb test/integration/provider_catalog_boot_flow_test.rb test/integration/seed_baseline_test.rb
```

Expected:

- no offenses

**Step 3: Re-read the design and plan against the landed diff**

Confirm the implementation still matches these decisions:

- `models.*.enabled` is required and deep-merge friendly
- disabled models produce `model_disabled`
- role selection skips disabled models
- explicit candidates hard-fail on disabled models
- sampling defaults are validated but still not wired into Phase 2 execution
- unknown `request_defaults` keys are rejected

**Step 4: Commit the verification clean-up if needed**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
git add core_matrix
git commit -m "test: verify llm catalog phase1 follow-up"
```

**Step 5: Hand off the outcome to the Phase 2 discussion**

Post a short summary in the Phase 2 discussion or follow-up note covering:

- the new catalog keys now available to Phase 2
- the deferred precedence work still needed in provider request assembly
- the invariant that disabled models must remain hidden and unusable everywhere

## Stop Point

Stop after the Phase 1 catalog contract, validation, selector behavior, tests,
sample config, and docs all land cleanly.

Do not implement these items in this task:

- provider request assembly
- agent loop execution
- `Turn.resolved_config_snapshot` merge changes
- agent-level, conversation-level, or turn-level runtime override precedence
- provider-specific compatibility shims for unsupported sampling knobs
