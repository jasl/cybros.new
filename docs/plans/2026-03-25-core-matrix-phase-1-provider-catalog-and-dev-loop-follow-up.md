# Core Matrix Phase 1 Provider Catalog And Dev Loop Follow-Up Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the narrow Phase 1 provider catalog with a Docker-friendly non-secret runtime catalog, make credential presence part of provider usability, add the built-in `mock_llm` development loop, and seed a usable `role:main` baseline for manual testing.

**Architecture:** Migrate the catalog entry point to `config/llm_catalog.yml` plus `config.d` overrides, then keep selector behavior centered on `role:main` while moving provider usability checks into one dedicated service. Adapt the reference `mock_llm` controllers into `core_matrix`, seed the dev provider and optional real-provider credentials idempotently, and keep mutable installation facts in `ProviderCredential`, `ProviderEntitlement`, and `ProviderPolicy`.

**Tech Stack:** Ruby on Rails, Active Record, YAML config loading, Active Record Encryption, Minitest, Action Dispatch request tests, Bun, Brakeman, Bundler Audit, RuboCop

---

### Task 1: Migrate The Catalog Entry Point To `llm_catalog.yml` And `config.d`

**Files:**
- Create: `core_matrix/config/llm_catalog.yml`
- Create: `core_matrix/config.d/.gitignore`
- Delete: `core_matrix/config/providers/catalog.yml`
- Modify: `core_matrix/app/services/provider_catalog/load.rb`
- Modify: `core_matrix/test/services/provider_catalog/load_test.rb`
- Modify: `core_matrix/test/integration/provider_catalog_boot_flow_test.rb`

**Step 1: Write the failing loader regressions for the new path and override precedence**

Add one test that fails unless the loader defaults to `config/llm_catalog.yml`, and one test that fails unless `config.d/llm_catalog.yml` plus `config.d/llm_catalog.test.yml` override the base file in order:

```ruby
Dir.mktmpdir do |dir|
  FileUtils.mkdir_p(File.join(dir, "config.d"))

  File.write(File.join(dir, "llm_catalog.yml"), <<~YAML)
    version: 1
    providers:
      openai:
        display_name: OpenAI
        enabled: true
        environments: [development, test, production]
        adapter_key: openai
        base_url: https://api.openai.com/v1
        headers: {}
        wire_api: chat_completions
        transport: http
        requires_credential: true
        credential_kind: api_key
        metadata: {}
        models: {}
    model_roles: {}
  YAML

  File.write(File.join(dir, "config.d", "llm_catalog.yml"), <<~YAML)
    providers:
      openai:
        headers:
          x-base-override: "1"
  YAML

  File.write(File.join(dir, "config.d", "llm_catalog.test.yml"), <<~YAML)
    providers:
      openai:
        headers:
          x-env-override: "1"
  YAML

  catalog = ProviderCatalog::Load.call(
    path: File.join(dir, "llm_catalog.yml"),
    override_dir: File.join(dir, "config.d"),
    env: "test"
  )

  assert_equal "1", catalog.provider("openai").dig(:headers, "x-env-override")
end
```

Update the boot flow test to load the shipped catalog from `config/llm_catalog.yml` instead of the old `config/providers/catalog.yml`.

**Step 2: Run the provider-catalog loader tests to verify failure**

Run:

```bash
cd core_matrix
bin/rails test test/services/provider_catalog/load_test.rb test/integration/provider_catalog_boot_flow_test.rb
```

Expected:

- failures mentioning the old default path or missing override support

**Step 3: Implement the new loader path and merge behavior**

Update `ProviderCatalog::Load` so it:

- defaults to `Rails.root.join("config/llm_catalog.yml")`
- reads optional override files from `Rails.root.join("config.d")`
- merges `llm_catalog.yml` and `llm_catalog.<env>.yml` in the documented order
- deep-merges hashes and replaces arrays wholesale
- raises a descriptive `MissingCatalog` error for the new base path

Create `core_matrix/config.d/.gitignore` so override YAML files stay out of git:

```gitignore
*
!.gitignore
```

Move the shipped base catalog content into `core_matrix/config/llm_catalog.yml` and delete `core_matrix/config/providers/catalog.yml`.

**Step 4: Run the loader tests again to verify they pass**

Run:

```bash
cd core_matrix
bin/rails test test/services/provider_catalog/load_test.rb test/integration/provider_catalog_boot_flow_test.rb
```

Expected:

- both tests pass against the new path and override semantics

**Step 5: Commit**

```bash
git -C .. add core_matrix/config/llm_catalog.yml core_matrix/config.d/.gitignore core_matrix/app/services/provider_catalog/load.rb core_matrix/test/services/provider_catalog/load_test.rb core_matrix/test/integration/provider_catalog_boot_flow_test.rb
git -C .. rm core_matrix/config/providers/catalog.yml
git -C .. commit -m "refactor: move provider catalog to llm_catalog"
```

### Task 2: Expand The Catalog Schema And Ship The New Provider Baseline

**Files:**
- Modify: `core_matrix/app/services/provider_catalog/validate.rb`
- Modify: `core_matrix/config/llm_catalog.yml`
- Modify: `core_matrix/test/services/provider_catalog/validate_test.rb`
- Modify: `core_matrix/test/services/provider_catalog/load_test.rb`
- Modify: `core_matrix/test/integration/provider_catalog_boot_flow_test.rb`
- Modify: `core_matrix/docs/behavior/provider-catalog-config-and-validation.md`

**Step 1: Write failing validator coverage for the expanded provider and model fields**

Extend the validator tests so a provider definition without `enabled`,
`environments`, `adapter_key`, `base_url`, `wire_api`, `transport`,
`requires_credential`, or `credential_kind` is rejected, and a model definition
without `api_model` or `tokenizer_hint` is rejected:

```ruby
error = assert_raises(ProviderCatalog::Validate::InvalidCatalog) do
  ProviderCatalog::Validate.call(
    version: 1,
    providers: {
      "openrouter" => {
        display_name: "OpenRouter",
        metadata: {},
        models: {
          "openai-gpt-5.4" => valid_model_definition,
        },
      },
    },
    model_roles: { "main" => ["openrouter/openai-gpt-5.4"] }
  )
end

assert_includes error.message, "enabled"
```

Add load-level assertions for the shipped catalog:

- `openrouter`, `dev`, `ollama`, and `llama_cpp` exist
- `dev` is environment-gated to `development` and `test`
- `openrouter` and `openai` require `api_key`
- `codex_subscription` requires `oauth_codex`
- `main` ends with `dev/mock-model` so `auto` can stay usable in development and test

**Step 2: Run the catalog validation tests to verify failure**

Run:

```bash
cd core_matrix
bin/rails test test/services/provider_catalog/validate_test.rb test/services/provider_catalog/load_test.rb test/integration/provider_catalog_boot_flow_test.rb
```

Expected:

- failures for the new required fields and the missing shipped provider entries

**Step 3: Implement the expanded schema and shipped catalog**

Update `ProviderCatalog::Validate` to preserve and validate the new catalog
fields. Keep the existing explicit capability validation and add new checks for:

- catalog `version`
- provider booleans, strings, hashes, and environment arrays
- `requires_credential` paired with `credential_kind`
- model `api_model` and `tokenizer_hint`
- optional model `request_defaults`

Expand `core_matrix/config/llm_catalog.yml` so it ships:

- `codex_subscription`
- `openai`
- `openrouter`
- `dev`
- `ollama`
- `llama_cpp`

Define `model_roles.main` so real providers come first, but `dev/mock-model`
remains the final test-friendly fallback in `development` and `test`.

Update the provider-catalog behavior doc so it describes the new file path,
override loading, expanded runtime metadata, and the retained config-versus-SQL
split.

**Step 4: Run the catalog tests again to verify they pass**

Run:

```bash
cd core_matrix
bin/rails test test/services/provider_catalog/validate_test.rb test/services/provider_catalog/load_test.rb test/integration/provider_catalog_boot_flow_test.rb
```

Expected:

- the validator and shipped-catalog assertions pass with the richer baseline

**Step 5: Commit**

```bash
git -C .. add core_matrix/app/services/provider_catalog/validate.rb core_matrix/config/llm_catalog.yml core_matrix/test/services/provider_catalog/validate_test.rb core_matrix/test/services/provider_catalog/load_test.rb core_matrix/test/integration/provider_catalog_boot_flow_test.rb core_matrix/docs/behavior/provider-catalog-config-and-validation.md
git -C .. commit -m "feat: expand llm catalog runtime metadata"
```

### Task 3: Add A Dedicated Provider Availability Service And Rewire Selector Resolution

**Files:**
- Create: `core_matrix/app/services/providers/check_availability.rb`
- Create: `core_matrix/test/services/providers/check_availability_test.rb`
- Modify: `core_matrix/app/services/workflows/resolve_model_selector.rb`
- Modify: `core_matrix/test/services/workflows/resolve_model_selector_test.rb`
- Modify: `core_matrix/test/integration/workflow_selector_flow_test.rb`
- Modify: `core_matrix/docs/behavior/provider-governance-models-and-services.md`
- Modify: `core_matrix/docs/behavior/workflow-model-selector-resolution.md`

**Step 1: Write the failing availability and selector regressions**

Add a service test for each unusable state:

```ruby
result = Providers::CheckAvailability.call(
  installation: installation,
  provider_handle: "openrouter",
  model_ref: "openai-gpt-5.4",
  env: "test"
)

assert_equal false, result.usable?
assert_equal "missing_credential", result.reason_key
```

Then add selector regressions showing:

- an explicit `candidate:openrouter/openai-gpt-5.4` fails immediately when the credential is missing
- `role:main` can skip missing-credential providers and fall through to `dev/mock-model` in test
- policy-disabled providers remain unusable even if credentials and entitlements exist

**Step 2: Run the availability and selector tests to verify failure**

Run:

```bash
cd core_matrix
bin/rails test test/services/providers/check_availability_test.rb test/services/workflows/resolve_model_selector_test.rb test/integration/workflow_selector_flow_test.rb
```

Expected:

- failures because availability logic is still embedded in selector code and ignores credentials and environment gating

**Step 3: Implement `Providers::CheckAvailability` and integrate it**

Create a small result object or struct that returns at least:

- `usable?`
- `reason_key`
- `provider_handle`
- `model_ref`

Make the service check, in order:

1. provider/model defined in the catalog
2. provider `enabled: true`
3. provider `environments` includes the current `Rails.env`
4. installation policy is not disabled
5. active entitlement exists
6. matching credential exists when `requires_credential: true`

Refactor `Workflows::ResolveModelSelector` to call the new service for every candidate and keep role-local fallback semantics unchanged.

Update the provider-governance and selector behavior docs so they describe catalog visibility, policy gating, credential requirements, and structured unavailable reasons explicitly.

**Step 4: Run the availability and selector tests again to verify they pass**

Run:

```bash
cd core_matrix
bin/rails test test/services/providers/check_availability_test.rb test/services/workflows/resolve_model_selector_test.rb test/integration/workflow_selector_flow_test.rb
```

Expected:

- the new service passes and selector fallback remains role-local

**Step 5: Commit**

```bash
git -C .. add core_matrix/app/services/providers/check_availability.rb core_matrix/test/services/providers/check_availability_test.rb core_matrix/app/services/workflows/resolve_model_selector.rb core_matrix/test/services/workflows/resolve_model_selector_test.rb core_matrix/test/integration/workflow_selector_flow_test.rb core_matrix/docs/behavior/provider-governance-models-and-services.md core_matrix/docs/behavior/workflow-model-selector-resolution.md
git -C .. commit -m "feat: add provider availability resolution"
```

### Task 4: Add The Built-In `mock_llm` Development/Test Surface

**Files:**
- Create: `core_matrix/app/controllers/mock_llm/v1/application_controller.rb`
- Create: `core_matrix/app/controllers/mock_llm/v1/chat_completions_controller.rb`
- Create: `core_matrix/app/controllers/mock_llm/v1/models_controller.rb`
- Modify: `core_matrix/config/routes.rb`
- Create: `core_matrix/test/requests/mock_llm/chat_completions_test.rb`
- Create: `core_matrix/test/requests/mock_llm/models_test.rb`

**Step 1: Write the failing request tests for the mock endpoints**

Add request coverage for:

- `GET /mock_llm/v1/models` returning the current `dev` models from the catalog
- `POST /mock_llm/v1/chat/completions` returning deterministic markdown for `!md hello`
- bare numeric prompts producing delayed-content text
- `!mock error=429 message=rate_limited -- hello` returning an OpenAI-shaped error payload

Example:

```ruby
post "/mock_llm/v1/chat/completions", params: {
  model: "mock-model",
  messages: [{ role: "user", content: "!md hello" }]
}, as: :json

assert_response :success
assert_match "# Mock Markdown", response.parsed_body.dig("choices", 0, "message", "content")
```

**Step 2: Run the mock request tests to verify failure**

Run:

```bash
cd core_matrix
bin/rails test test/requests/mock_llm/models_test.rb test/requests/mock_llm/chat_completions_test.rb
```

Expected:

- route or controller missing failures

**Step 3: Copy and adapt the reference mock controllers**

Bring the `references/original/cybros/app/controllers/mock_llm` implementation into `core_matrix` and adapt it so:

- the routes are mounted only in `development` and `test`
- `ModelsController#index` reads the `dev` provider models from the current catalog instead of hardcoding them
- the retained prompt controls, numeric delay shortcut, streaming support, and OpenAI-compatible error payloads keep working

**Step 4: Run the mock request tests again to verify they pass**

Run:

```bash
cd core_matrix
bin/rails test test/requests/mock_llm/models_test.rb test/requests/mock_llm/chat_completions_test.rb
```

Expected:

- both request tests pass in `test`

**Step 5: Commit**

```bash
git -C .. add core_matrix/app/controllers/mock_llm core_matrix/config/routes.rb core_matrix/test/requests/mock_llm
git -C .. commit -m "feat: add mock llm development surface"
```

### Task 5: Seed A Usable `role:main` Baseline For Development And Manual Testing

**Files:**
- Modify: `core_matrix/db/seeds.rb`
- Modify: `core_matrix/test/integration/seed_baseline_test.rb`
- Modify: `core_matrix/test/integration/provider_governance_flow_test.rb`
- Create: `core_matrix/test/support/environment_overrides.rb`

**Step 1: Write the failing seed-baseline regressions**

Extend `seed_baseline_test.rb` so it proves:

- running `db/seeds.rb` twice creates the minimal `dev` entitlement and policy rows without duplicating them
- `OPENROUTER_API_KEY` or `OPENAI_API_KEY` causes the corresponding `ProviderCredential` row to be upserted
- seeded real-provider credentials plus seeded entitlements leave `role:main` usable without changing `Conversation` selector mode away from `auto`

Use a reusable helper for temporary environment overrides:

```ruby
with_modified_env("OPENROUTER_API_KEY" => "or-live-123") do
  load Rails.root.join("db/seeds.rb")
end

assert_equal "api_key", ProviderCredential.find_by!(provider_handle: "openrouter").credential_kind
```

**Step 2: Run the seed and governance tests to verify failure**

Run:

```bash
cd core_matrix
bin/rails test test/integration/seed_baseline_test.rb test/integration/provider_governance_flow_test.rb
```

Expected:

- failures because seeds do not yet create dev governance rows or import real-provider credentials from environment variables

**Step 3: Extend seeds with idempotent provider-governance upserts**

Update `db/seeds.rb` to:

- keep bundled runtime reconciliation intact
- upsert the `dev` provider's default enabled policy and active entitlement when an installation exists
- read `OPENAI_API_KEY` and `OPENROUTER_API_KEY`
- upsert matching `ProviderCredential` rows through `ProviderCredentials::UpsertSecret`
- ensure providers with seeded credentials also receive the minimal entitlement and enabled policy needed to be usable

Add `test/support/environment_overrides.rb` so the environment-variable helper is reusable instead of reimplemented per test.

**Step 4: Run the targeted seed tests again to verify they pass**

Run:

```bash
cd core_matrix
bin/rails test test/integration/seed_baseline_test.rb test/integration/provider_governance_flow_test.rb
```

Expected:

- the seed baseline remains idempotent and real-provider credentials are seeded correctly

**Step 5: Run the full `core_matrix` verification suite**

Run:

```bash
cd core_matrix
bin/brakeman --no-pager
bin/bundler-audit
bin/rubocop -f github
bun run lint:js
bin/rails db:test:prepare test
bin/rails db:test:prepare test:system
```

Expected:

- the full verification suite passes serially

**Step 6: Commit**

```bash
git -C .. add core_matrix/db/seeds.rb core_matrix/test/integration/seed_baseline_test.rb core_matrix/test/integration/provider_governance_flow_test.rb core_matrix/test/support/environment_overrides.rb
git -C .. commit -m "feat: seed provider dev loop baseline"
```
