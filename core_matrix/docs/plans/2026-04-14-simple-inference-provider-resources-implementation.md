# Simple Inference Provider Resources Rollout Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the helper-centric `simple_inference` client with resource-oriented `responses` and `images` resources, migrate `core_matrix` to capability-driven dispatch, and upgrade MockLLM to the modern API shapes needed for deterministic testing.

**Architecture:** Expand `core_matrix`'s validated provider catalog so capability metadata and runtime request context can drive planning instead of `wire_api` branches. In `simple_inference`, introduce resource objects, capability profiles, request planning, and normalized result types, then hang OpenAI, OpenRouter, Gemini, and Anthropic protocol adapters behind those resource contracts. Finish by switching `core_matrix` dispatch and normalization to the new result contracts and aligning MockLLM with the canonical Responses and Images shapes used in tests and acceptance flows.

**Tech Stack:** Ruby, Rails, Minitest, ActionController::Live SSE, vendored gem development in `core_matrix/vendor/simple_inference`, Fiber-friendly HTTP adapters (`Net::HTTP` and `httpx`).

## Status Snapshot

Completed on this branch:

- Tasks 1 through 6 from this document
- full static verification, Rails test suites, vendored gem suite, and active acceptance including the 2048 capstone
- checkpoint commit `56641a53 feat: add provider resources foundation`
- the current head on this branch additionally lands phase-2 streaming work:
  - explicit `ToolCallDelta` and `ToolCallDone` SDK events
  - native Gemini and Anthropic streaming paths
  - live `core_matrix` text-delta forwarding for streaming-capable providers
  - runtime stream failure signaling when a round is superseded by tool continuation
  - manual OpenRouter image smoke validation against `openai/gpt-5-image`
    and `google/gemini-3.1-flash-image-preview`

Known gaps after that checkpoint:

- the design doc originally promised more `responses` methods than were shipped
- `Responses::Stream` is still intentionally narrow at the `core_matrix`
  integration layer even though the SDK now exposes text and tool-call events
- `core_matrix` still only consumes `TextDelta` during provider streaming
- `core_matrix` still does not expose product-level image generation
- request-level capability flags remain in `simple_inference`, not `core_matrix`

Manual provider validation completed during phase 2:

- `openai/gpt-5-image` works through the current OpenRouter image path
- `google/gemini-3.1-flash-image-preview` works through the current OpenRouter image path
- real OpenRouter image payloads may surface image bytes as a `data:` URL inside
  `message.images[*].image_url.url`, so normalization must not assume
  `b64_json` is always present

## Phase 2 Scope

This batch focused on streaming fidelity and real-provider validation, not on
widening the product surface area.

### Task 7: Tighten The Documents Around The Real Shipped Surface

- revise the design doc so committed APIs and deferred APIs are clearly split
- keep `core_matrix` image generation explicitly deferred
- document that request policy flags are SDK-only for now
- document that Gemini and Anthropic now use native streaming paths in the SDK,
  while `core_matrix` still only forwards text deltas

### Task 8: Expand `simple_inference` Streaming Semantics

Files expected to change:

- `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/vendor/simple_inference/lib/simple_inference/responses/stream.rb`
- `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/vendor/simple_inference/lib/simple_inference/protocols/openai_responses.rb`
- `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/vendor/simple_inference/lib/simple_inference/protocols/gemini_generate_content.rb`
- `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/vendor/simple_inference/lib/simple_inference/protocols/anthropic_messages.rb`
- focused protocol and stream tests under `core_matrix/vendor/simple_inference/test`

Acceptance target:

- preserve `TextDelta`
- add explicit tool-call stream events where the provider exposes enough data
- keep `Completed` as the authoritative final normalized result
- use native provider streaming when practical; otherwise keep behavior explicit

### Task 9: Make `core_matrix` Streaming Capability-Aware

Files expected to change:

- `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/provider_execution/dispatch_request.rb`
- `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/provider_execution/execute_round_loop.rb`
- `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/provider_execution/execute_turn_step.rb`
- focused provider execution tests

Acceptance target:

- only request provider streaming when model capability says `streaming: true`
- preserve final-round deltas for tool-enabled turns
- keep retry behavior correct when no deltas have been emitted yet

### Task 10: Manually Validate OpenRouter Image Models

Manual smoke validation only in this phase:

- `openai/gpt-5-image`
- `google/gemini-3.1-flash-image-preview`

This phase validates that the already-added SDK image path works against real
OpenRouter models. It does not add `core_matrix` product routing yet.

---

### Task 1: Expand The Catalog And Runtime Capability Contract

**Files:**
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/provider_catalog/validate.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/models/provider_request_context.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/provider_execution/build_request_context.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/config/llm_catalog.yml`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/fixtures/files/llm_catalog.yml`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/provider_catalog/validate_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/models/provider_request_context_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/workflows/build_execution_snapshot_test.rb`

**Step 1: Write failing catalog and context tests**

Add assertions for these fields:

```ruby
capabilities = provider_definition.fetch(:models).fetch("gpt-5").fetch(:capabilities)
assert_equal true, capabilities.fetch(:streaming)
assert_equal true, capabilities.fetch(:conversation_state)
assert_equal false, capabilities.fetch(:provider_builtin_tools)
assert_equal true, capabilities.fetch(:image_generation)
```

Add a request-context assertion for:

```ruby
assert_equal true, context.capabilities.fetch("streaming")
assert_equal false, context.capabilities.fetch("provider_builtin_tools")
```

**Step 2: Run targeted tests and confirm they fail**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test test/services/provider_catalog/validate_test.rb test/models/provider_request_context_test.rb test/services/workflows/build_execution_snapshot_test.rb
```

Expected: failures about missing capability keys and missing `capabilities` in `ProviderRequestContext`.

**Step 3: Implement the schema expansion**

- Extend the validated capability payload to include:
  - `streaming`
  - `conversation_state`
  - `provider_builtin_tools`
  - `image_generation`
- Add `capabilities` as a required hash in `ProviderRequestContext`.
- Build the normalized capability snapshot in `BuildRequestContext`.
- Update the shipped catalog and fixture catalog so supported models declare the new flags explicitly.

**Step 4: Re-run the targeted tests**

Run the same command from Step 2.

Expected: all tests pass.

**Step 5: Commit**

```bash
git add core_matrix/app/services/provider_catalog/validate.rb core_matrix/app/models/provider_request_context.rb core_matrix/app/services/provider_execution/build_request_context.rb core_matrix/config/llm_catalog.yml core_matrix/test/fixtures/files/llm_catalog.yml core_matrix/test/services/provider_catalog/validate_test.rb core_matrix/test/models/provider_request_context_test.rb core_matrix/test/services/workflows/build_execution_snapshot_test.rb
git commit -m "feat: expand provider capability contract"
```

### Task 2: Introduce The Resource-Oriented `simple_inference` Surface

**Files:**
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/vendor/simple_inference/lib/simple_inference.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/vendor/simple_inference/lib/simple_inference/client.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/vendor/simple_inference/lib/simple_inference/resources/responses.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/vendor/simple_inference/lib/simple_inference/resources/images.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/vendor/simple_inference/lib/simple_inference/capabilities/provider_profile.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/vendor/simple_inference/lib/simple_inference/capabilities/model_profile.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/vendor/simple_inference/lib/simple_inference/planning/request_planner.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/vendor/simple_inference/lib/simple_inference/responses/result.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/vendor/simple_inference/lib/simple_inference/responses/stream.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/vendor/simple_inference/lib/simple_inference/images/result.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/vendor/simple_inference/test/test_simple_inference_client.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/vendor/simple_inference/test/test_resources_contract.rb`

**Step 1: Write failing resource contract tests**

Add tests that enforce:

```ruby
client = SimpleInference::Client.new(base_url: "https://example.test", api_key: "test")
assert_respond_to client, :responses
assert_respond_to client, :images
assert_respond_to client.responses, :create
assert_respond_to client.responses, :stream
assert_respond_to client.images, :generate
refute_respond_to client, :chat
```

**Step 2: Run the gem contract tests and confirm they fail**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix/vendor/simple_inference
bundle exec ruby -Itest test/test_simple_inference_client.rb
bundle exec ruby -Itest test/test_resources_contract.rb
```

Expected: failures because the current client subclasses `OpenAICompatible` and still exposes helper methods instead of resources.

**Step 3: Implement the new client surface**

- Replace inheritance-based `Client < Protocols::OpenAICompatible` with a composition-based client that owns:
  - config
  - adapter
  - provider/model profile input
  - `responses`
  - `images`
- Add minimal normalized result and stream classes so the resource contracts are explicit.
- Add a request planner entry point that can reject impossible requests before hitting a protocol adapter.

**Step 4: Re-run the targeted gem tests**

Run the commands from Step 2 plus:

```bash
bundle exec ruby -Itest test/test_protocol_contract.rb
```

Expected: the client contract tests pass and existing low-level protocol contract coverage still passes after the API surface change.

**Step 5: Commit**

```bash
git add core_matrix/vendor/simple_inference/lib/simple_inference.rb core_matrix/vendor/simple_inference/lib/simple_inference/client.rb core_matrix/vendor/simple_inference/lib/simple_inference/resources core_matrix/vendor/simple_inference/lib/simple_inference/capabilities core_matrix/vendor/simple_inference/lib/simple_inference/planning core_matrix/vendor/simple_inference/lib/simple_inference/responses core_matrix/vendor/simple_inference/lib/simple_inference/images core_matrix/vendor/simple_inference/test/test_simple_inference_client.rb core_matrix/vendor/simple_inference/test/test_resources_contract.rb
git commit -m "refactor: add resource-oriented simple inference client"
```

### Task 3: Port Protocol Adapters For Responses And Images

**Files:**
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/vendor/simple_inference/lib/simple_inference/protocols/openai_responses.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/vendor/simple_inference/lib/simple_inference/protocols/openai_images.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/vendor/simple_inference/lib/simple_inference/protocols/openrouter_responses.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/vendor/simple_inference/lib/simple_inference/protocols/openrouter_images.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/vendor/simple_inference/lib/simple_inference/protocols/gemini_generate_content.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/vendor/simple_inference/lib/simple_inference/protocols/anthropic_messages.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/vendor/simple_inference/test/test_openai_responses_protocol.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/vendor/simple_inference/test/test_openai_images_protocol.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/vendor/simple_inference/test/test_openrouter_protocols.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/vendor/simple_inference/test/test_gemini_protocol.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/vendor/simple_inference/test/test_anthropic_protocol.rb`

**Step 1: Write failing adapter tests**

Add one focused contract test per provider path:

- OpenAI `responses.create` returns `SimpleInference::Responses::Result`
- OpenAI `images.generate` normalizes `data[*].b64_json`
- OpenRouter image generation maps `chat/completions` image payloads into normalized image items
- Gemini `generateContent` maps content parts and function declarations
- Anthropic `messages` maps content blocks and tool use blocks

**Step 2: Run targeted adapter tests and confirm they fail**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix/vendor/simple_inference
bundle exec ruby -Itest test/test_openai_responses_protocol.rb
bundle exec ruby -Itest test/test_openai_images_protocol.rb
bundle exec ruby -Itest test/test_openrouter_protocols.rb
bundle exec ruby -Itest test/test_gemini_protocol.rb
bundle exec ruby -Itest test/test_anthropic_protocol.rb
```

Expected: missing files or failing assertions for unimplemented protocol adapters.

**Step 3: Implement the adapters**

- Refit `OpenAIResponses` so it plugs into the new resource/result classes instead of exposing a separate protocol-specific result struct.
- Implement OpenAI images at `/images/generations`.
- Implement OpenRouter text/images with conservative built-in-tool handling and OpenAI-style normalized results.
- Implement Gemini `generateContent` plus streaming mapping.
- Implement Anthropic `messages` plus streaming mapping.

**Step 4: Re-run targeted adapter tests**

Run the commands from Step 2 and then:

```bash
bundle exec rake
```

Expected: targeted adapter tests pass and the full vendored gem test suite passes.

**Step 5: Commit**

```bash
git add core_matrix/vendor/simple_inference/lib/simple_inference/protocols core_matrix/vendor/simple_inference/test/test_openai_responses_protocol.rb core_matrix/vendor/simple_inference/test/test_openai_images_protocol.rb core_matrix/vendor/simple_inference/test/test_openrouter_protocols.rb core_matrix/vendor/simple_inference/test/test_gemini_protocol.rb core_matrix/vendor/simple_inference/test/test_anthropic_protocol.rb
git commit -m "feat: add provider resource adapters"
```

### Task 4: Migrate `core_matrix` Dispatch And Normalization

**Files:**
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/provider_execution/dispatch_request.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/provider_gateway/dispatch_text.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/provider_execution/normalize_provider_response.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/provider_usage/normalize_metrics.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/models/provider_request_settings_schema.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/provider_execution/dispatch_request_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/provider_execution/normalize_provider_response_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/provider_usage/normalize_metrics_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/provider_execution/build_http_adapter_test.rb`

**Step 1: Write failing runtime tests**

Add tests that prove:

- dispatch uses `client.responses.create` or `client.responses.stream` instead of `client.chat`
- request planning consults `request_context.capabilities`
- normalization operates on explicit result classes instead of `respond_to?(:output_items)`
- image-generation routing has a dedicated resource call path where covered

**Step 2: Run targeted runtime tests and confirm they fail**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test test/services/provider_execution/dispatch_request_test.rb test/services/provider_execution/normalize_provider_response_test.rb test/services/provider_usage/normalize_metrics_test.rb test/services/provider_execution/build_http_adapter_test.rb
```

Expected: failures because dispatch still branches on `wire_api` and normalization still uses structural detection.

**Step 3: Implement the runtime migration**

- Build `SimpleInference::Client` with profile/planner inputs instead of protocol subclasses leaking into service objects.
- Route text generation through `client.responses`.
- Normalize from explicit `SimpleInference::Responses::Result` and `SimpleInference::Images::Result`.
- Keep transport metadata only where HTTP adapter selection still needs it.

**Step 4: Re-run targeted runtime tests**

Run the command from Step 2 and then:

```bash
bin/rails test test/services/provider_gateway/dispatch_text_test.rb
```

Expected: all targeted runtime tests pass.

**Step 5: Commit**

```bash
git add core_matrix/app/services/provider_execution/dispatch_request.rb core_matrix/app/services/provider_gateway/dispatch_text.rb core_matrix/app/services/provider_execution/normalize_provider_response.rb core_matrix/app/services/provider_usage/normalize_metrics.rb core_matrix/app/models/provider_request_settings_schema.rb core_matrix/test/services/provider_execution/dispatch_request_test.rb core_matrix/test/services/provider_execution/normalize_provider_response_test.rb core_matrix/test/services/provider_usage/normalize_metrics_test.rb core_matrix/test/services/provider_execution/build_http_adapter_test.rb
git commit -m "refactor: migrate core matrix provider dispatch"
```

### Task 5: Upgrade MockLLM And Test Support To The New API Shapes

**Files:**
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/controllers/mock_llm/v1/responses_controller.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/controllers/mock_llm/v1/images_controller.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/controllers/mock_llm/v1/application_controller.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/config/routes.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/support/provider_execution_test_support.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/requests/mock_llm/responses_test.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/requests/mock_llm/images_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/requests/mock_llm/chat_completions_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/config/llm_catalog.yml`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/fixtures/files/llm_catalog.yml`

**Step 1: Write failing mock API tests**

Add request tests for:

- `POST /mock_llm/v1/responses`
- SSE responses events such as `response.output_text.delta` and `response.completed`
- `POST /mock_llm/v1/images/generations`
- structured input parts including `input_text` and `input_image`

**Step 2: Run targeted mock tests and confirm they fail**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test test/requests/mock_llm/chat_completions_test.rb test/requests/mock_llm/responses_test.rb test/requests/mock_llm/images_test.rb
```

Expected: route and controller failures for the new endpoints.

**Step 3: Implement the mock providers**

- Add a canonical mock Responses controller with deterministic non-streaming and streaming behavior.
- Emit OpenAI-style `response.*` SSE events.
- Add a deterministic image-generation endpoint that returns normalized image payloads suitable for tests.
- Update test helpers so fake adapters and mock catalogs target the canonical Responses and Images shapes.

**Step 4: Re-run targeted mock tests**

Run the command from Step 2 plus:

```bash
bin/rails test test/services/provider_execution/execute_turn_step_test.rb test/services/provider_execution/token_estimator_test.rb
```

Expected: request and supporting service tests pass with the updated mock shapes.

**Step 5: Commit**

```bash
git add core_matrix/app/controllers/mock_llm/v1/responses_controller.rb core_matrix/app/controllers/mock_llm/v1/images_controller.rb core_matrix/app/controllers/mock_llm/v1/application_controller.rb core_matrix/config/routes.rb core_matrix/test/support/provider_execution_test_support.rb core_matrix/test/requests/mock_llm/chat_completions_test.rb core_matrix/test/requests/mock_llm/responses_test.rb core_matrix/test/requests/mock_llm/images_test.rb core_matrix/config/llm_catalog.yml core_matrix/test/fixtures/files/llm_catalog.yml
git commit -m "feat: align mock llm with resource APIs"
```

### Task 6: Full Verification, Acceptance, And Review

**Files:**
- Review: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/docs/plans/2026-04-14-simple-inference-provider-resources-design.md`
- Review: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/docs/plans/2026-04-14-simple-inference-provider-resources-implementation.md`
- Review: implementation diff across `core_matrix` and `core_matrix/vendor/simple_inference`

**Step 1: Run the vendored gem suite**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix/vendor/simple_inference
bundle exec rake
```

Expected: exit 0.

**Step 2: Run the full `core_matrix` verification suite**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/brakeman --no-pager
bin/bundler-audit
bin/rubocop -f github
bun run lint:js
bin/rails db:test:prepare
bin/rails test
bin/rails test:system
```

Expected: exit 0 for each command.

**Step 3: Run the full acceptance suite including 2048**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
ACTIVE_ACCEPTANCE_ENABLE_2048_CAPSTONE=1 bash acceptance/bin/run_active_suite.sh
```

Expected: exit 0, relevant acceptance artifacts generated, and resulting database state inspected for correct business data shape.

**Step 4: Run final review against the design**

- Dispatch one reviewer against the revised design doc for spec completeness.
- Dispatch one reviewer against the final code for correctness and integration quality.
- Dispatch one reviewer against the acceptance/runtime behavior for drift between document and implementation.

**Step 5: Final commit**

```bash
git add core_matrix/docs/plans/2026-04-14-simple-inference-provider-resources-design.md core_matrix/docs/plans/2026-04-14-simple-inference-provider-resources-implementation.md
git commit -m "chore: finalize provider resources rollout"
```
