# Simple Inference Provider Resources Design

## Goal

Redesign `core_matrix/vendor/simple_inference` into a capability-driven,
resource-oriented Ruby client that:

- treats OpenAI behavior as canonical where we implement OpenAI-standard APIs
- cleanly adapts OpenRouter, Gemini, Anthropic, and later Volcengine
- exposes explicit, Ruby-first resources instead of chat-helper-centric APIs
- preserves Fiber Scheduler friendliness and low-dependency extensibility
- lets `core_matrix` route by model capability instead of wire-protocol guesswork

## Design Principles

This branch explicitly allows breaking changes. The library is project-owned and
does not need compatibility shims for old internal callers.

Priority order:

1. long-term provider abstraction clarity
2. explicit capability control
3. Ruby-first API design
4. Fiber-friendly transport and streaming behavior
5. implementation cost

Additional constraints from this design discussion:

- OpenAI-standard behavior should follow official OpenAI behavior by default.
- Built-in tool support must be explicitly disable-able because third-party
  providers often implement only a subset of OpenAI cloud tools.
- Multimodal input support must be explicitly disable-able even when a model can
  theoretically accept those inputs.
- `core_matrix/config/llm_catalog.yml` is the local source of truth for planned
  model support and should drive capability decisions.

## Scope

This design covers:

1. the public object model for `simple_inference`
2. provider and model capability abstraction
3. `responses` as the primary text / tool / multimodal interaction resource
4. `images` as the primary image-generation resource
5. OpenAI, OpenRouter, Gemini, and Anthropic provider support
6. future Volcengine support at the protocol boundary
7. `core_matrix` migration from wire-API branching to capability-driven dispatch
8. test and verification strategy for the library and `core_matrix`

This design does not require in this first implementation pass:

- full OpenAI SDK typed-model parity
- every provider feature beyond `responses` and `images`
- image editing or image variations
- embeddings, audio, moderation, or transcription redesign
- full `core_matrix` product adoption of Gemini / Anthropic selectors on day one
- full catalog-driven image task routing for every future provider on day one

## Reference Material

Local references used to shape this design:

- [openai-ruby](/Users/jasl/Workspaces/Ruby/cybros/references/original/references/openai-ruby/README.md)
- [openai-ruby responses resource](/Users/jasl/Workspaces/Ruby/cybros/references/original/references/openai-ruby/lib/openai/resources/responses.rb)
- [ruby_llm provider base](/Users/jasl/Workspaces/Ruby/cybros/references/original/references/ruby_llm/lib/ruby_llm/provider.rb)
- [ruby_llm openrouter images](/Users/jasl/Workspaces/Ruby/cybros/references/original/references/ruby_llm/lib/ruby_llm/providers/openrouter/images.rb)
- [ruby_llm gemini chat](/Users/jasl/Workspaces/Ruby/cybros/references/original/references/ruby_llm/lib/ruby_llm/providers/gemini/chat.rb)
- [ruby_llm anthropic chat](/Users/jasl/Workspaces/Ruby/cybros/references/original/references/ruby_llm/lib/ruby_llm/providers/anthropic/chat.rb)
- [llm_catalog.yml](/Users/jasl/Workspaces/Ruby/cybros/core_matrix/config/llm_catalog.yml)

External API references that should guide behavior:

- [OpenAI Responses API](https://platform.openai.com/docs/api-reference/responses)
- [OpenAI Image Generation Guide](https://platform.openai.com/docs/guides/images/image-generation)
- [OpenRouter Image Generation](https://openrouter.ai/docs/guides/overview/multimodal/image-generation)
- [Gemini GenerateContent API](https://ai.google.dev/api/generate-content)
- [Gemini Function Calling](https://ai.google.dev/gemini-api/docs/function-calling)
- [Anthropic Messages API](https://platform.claude.com/docs/api/messages)
- [Anthropic Vision](https://docs.anthropic.com/en/docs/build-with-claude/vision)
- [Volcengine Responses API migration](https://www.volcengine.com/docs/82379/1585128)
- [Volcengine create response](https://www.volcengine.com/docs/82379/1569618)
- [Volcengine image generation](https://www.volcengine.com/docs/82379/1666945)

## Current Baseline

Today `simple_inference` is split across:

- a default `SimpleInference::Client` that is effectively an
  OpenAI-compatible chat-completions client
- a separate `SimpleInference::Protocols::OpenAIResponses`
  implementation that already powers `core_matrix` response-mode providers
- a helper-centric API that mixes transport concerns, protocol adaptation, and
  result aggregation

`core_matrix` currently branches by `wire_api` and instantiates:

- `SimpleInference::Client` for `chat_completions`
- `SimpleInference::Protocols::OpenAIResponses` for `responses`

At the same time, `core_matrix` has already moved part of the provider contract
forward in two important ways:

- `core_matrix/config/llm_catalog.yml` is now schema-validated at load time
- provider and model metadata are normalized into `ProviderRequestContext`, but
  that context still does not include a capability snapshot

The validated catalog currently guarantees these model capability fields:

- `text_output`
- `tool_calls`
- `structured_output`
- `multimodal_inputs.image`
- `multimodal_inputs.audio`
- `multimodal_inputs.video`
- `multimodal_inputs.file`

It does not yet represent:

- `streaming`
- `conversation_state`
- `provider_builtin_tools`
- `image_generation`
- resource-specific routing metadata beyond provider-level `wire_api` and
  `responses_path`

Mock infrastructure is also behind the desired API surface:

- `MockLLM` currently exposes `GET /models` and `POST /chat/completions`
- there is no mock `POST /responses`
- there is no mock image-generation endpoint
- the dev catalog can label a mock provider as `responses`, but there is no
  dedicated wire-level mock Responses controller backing that path

This creates several structural problems:

1. the public API shape is biased toward OpenAI-compatible chat helpers
2. provider adaptation leaks into `core_matrix` service objects
3. OpenAI responses support exists but is not a first-class resource object
4. image generation has no unified abstraction
5. future Gemini / Anthropic support would likely fork more call sites
6. capability decisions are split between protocol shape, model naming, and ad
   hoc caller assumptions

## Core Problem

The library needs to abstract by product capability, not by whichever HTTP
surface a provider happens to expose.

`core_matrix` cares about questions like:

- can this model accept image input?
- can this provider perform tool calls?
- should built-in cloud tools be disabled for this request?
- can this model generate images?
- can this provider maintain response state natively?

Those are not the same thing as:

- is this provider OpenAI-compatible?
- does this provider expose `chat/completions`?
- does this provider expose `responses`?

The current architecture overweights the latter and underweights the former.

## Recommended Architecture

### 1. Public API Becomes Resource-Oriented

`SimpleInference::Client` should become a thin entry point that exposes explicit
resources:

```ruby
client = SimpleInference::Client.new(...)

client.responses.create(...)
client.responses.stream(...)
client.responses.retrieve(...)
client.responses.delete(...)
client.responses.context(...)

client.images.generate(...)
```

The old top-level helper methods should be removed instead of preserved behind
compatibility shims:

- remove `client.chat(...)`
- remove `client.chat_stream(...)`
- remove overloaded `client.responses(...)`

This is the cleanest break and matches the intended long-term direction.

### 2. Provider Adaptation Moves Behind Resource Contracts

Each resource should delegate to a request planner and provider-specific
protocol adapter.

Recommended shape:

```ruby
SimpleInference::Client
SimpleInference::Resources::Responses
SimpleInference::Resources::Images
SimpleInference::Capabilities::ProviderProfile
SimpleInference::Capabilities::ModelProfile
SimpleInference::Planning::RequestPlanner
SimpleInference::Protocols::OpenAIResponses
SimpleInference::Protocols::OpenAIImages
SimpleInference::Protocols::OpenRouterChatImages
SimpleInference::Protocols::GeminiGenerateContent
SimpleInference::Protocols::GeminiPredictImages
SimpleInference::Protocols::AnthropicMessages
```

Responsibility split:

- resource object
  - stable Ruby API
  - returns normalized result objects
- request planner
  - validates capability gates
  - selects protocol adapter
  - strips or rejects unsupported request features
- protocol adapter
  - renders provider-specific payloads
  - executes transport requests
  - parses provider response shapes
- normalized result object
  - presents stable data to callers

### 3. Capability Is Explicit And Two-Layered

Capability decisions should come from two sources:

1. static model capability
   - source of truth: `core_matrix/config/llm_catalog.yml`
2. per-request policy toggles
   - caller-supplied allow / disable options

Recommended normalized capability fields:

- `text_output`
- `tool_calls`
- `structured_output`
- `streaming`
- `conversation_state`
- `provider_builtin_tools`
- `image_generation`
- `multimodal_inputs.image`
- `multimodal_inputs.audio`
- `multimodal_inputs.video`
- `multimodal_inputs.file`

Recommended per-request toggles:

- `allow_builtin_tools:`
- `allow_multimodal_inputs:`
- `allow_image_input:`
- `allow_audio_input:`
- `allow_video_input:`
- `allow_file_input:`
- `allow_image_generation:`
- `prefer_stateful_responses:`

Rules:

- if catalog says a capability is unsupported, reject before dispatch
- if catalog says a capability is supported but the request disables it, the
  planner must strip or reject corresponding fields
- provider-specific built-in tools must be treated separately from ordinary
  function tools

Implementation note:

- this is a schema expansion from the current catalog contract, not merely a
  reinterpretation of fields that already exist
- `ProviderCatalog::Validate`, fixture catalogs, and any request-settings
  validation tied to `wire_api` must be updated before the planner can rely on
  the additional capability flags

### 4. OpenAI Behavior Is Canonical Where Applicable

When the chosen provider path is OpenAI-standard, behavior should follow OpenAI
semantics first.

Examples:

- `responses.create` should follow OpenAI request / response field naming
- `previous_response_id` should behave like OpenAI conversation-state chaining
- OpenAI tool payloads should follow OpenAI semantics
- OpenAI image generation should use the standard images API shape

Third-party providers may be looser or partial; the planner and protocol
adapter should decide whether to:

- pass fields through unchanged
- strip unsupported fields
- reject with a capability error

### 5. `responses` Is The Canonical Text / Tool Resource

Even though some providers still use chat-oriented APIs, the public abstraction
for text generation should be `responses`.

Internal mappings:

- OpenAI -> `/responses`
- Volcengine -> native responses endpoints
- Gemini -> `models/*:generateContent` and streaming equivalent
- Anthropic -> `v1/messages`
- OpenRouter
  - initial text support may still render to chat-completions-compatible
    payloads
  - public caller still uses `client.responses`

This keeps `core_matrix` aligned around a single interaction concept instead of
bifurcating into `chat` and `responses`.

### 6. `images` Is The Canonical Image Generation Resource

Image generation should be a separate resource rather than a special-case
response helper.

Internal mappings:

- OpenAI -> `/images/generations`
- Volcengine -> image generation API
- OpenRouter -> `/chat/completions` with `modalities`
- Gemini
  - image-generation endpoint or provider-specific prediction endpoint
- Anthropic
  - not implemented initially unless a stable image-generation product path is
    explicitly supported

This decouples image generation from text-response modeling and avoids
pretending every provider offers identical image APIs.

## Resource Contracts

### Responses Resource

Recommended public methods:

```ruby
client.responses.create(model:, input:, **options)
client.responses.stream(model:, input:, **options)
client.responses.retrieve(response_id:, **options)
client.responses.delete(response_id:, **options)
client.responses.context(response_id:, **options)
```

Recommended request options:

- `instructions:`
- `previous_response_id:`
- `tools:`
- `tool_choice:`
- `include:`
- `reasoning:`
- `max_output_tokens:`
- `temperature:`
- `top_p:`
- `metadata:`
- `allow_builtin_tools:`
- `allow_multimodal_inputs:`
- `allow_image_input:`
- `allow_file_input:`
- `prefer_stateful_responses:`

Recommended result object:

```ruby
SimpleInference::Responses::Result
```

With fields:

- `id`
- `output_text`
- `output_items`
- `tool_calls`
- `usage`
- `finish_reason`
- `provider_response`

### Responses Stream

Recommended stream object:

```ruby
SimpleInference::Responses::Stream
```

Methods:

- `each`
- `text`
- `get_output_text`
- `get_final_result`
- `until_done`
- `close`

Recommended event hierarchy:

- `SimpleInference::Responses::Events::Raw`
- `SimpleInference::Responses::Events::TextDelta`
- `SimpleInference::Responses::Events::TextDone`
- `SimpleInference::Responses::Events::ToolCallDelta`
- `SimpleInference::Responses::Events::ToolCallDone`
- `SimpleInference::Responses::Events::Completed`

Important design choice:

- do not attempt full typed parity with `openai-ruby`
- do provide stable Ruby event objects with:
  - `type`
  - `raw`
  - `snapshot` when meaningful

### Images Resource

Recommended public method:

```ruby
client.images.generate(model:, prompt: nil, input: nil, **options)
```

Recommended request options:

- `size:`
- `quality:`
- `background:`
- `moderation:`
- `output_format:`
- `n:`
- `allow_multimodal_inputs:`
- `allow_image_generation:`

Recommended result object:

```ruby
SimpleInference::Images::Result
```

With fields:

- `images`
- `usage`
- `provider_response`
- `provider_format`
- `output_text`

Normalized image item fields:

- `url`
- `b64_json`
- `data_url`
- `mime_type`
- `revised_prompt`
- `raw`

## Provider Strategy

### OpenAI

Use OpenAI-native resources:

- `responses` -> native Responses API
- `images.generate` -> native Images API

OpenAI behavior is the baseline reference implementation for:

- request shape
- usage semantics
- response item naming
- `previous_response_id`
- built-in tool semantics where supported

### OpenRouter

Use OpenRouter where it is strong, but keep the public API provider-neutral.

Text path:

- initial implementation may render `responses` requests into
  chat-completions-compatible payloads when routed to OpenRouter

Image path:

- `images.generate` should use `/chat/completions`
- set `modalities` as required by OpenRouter image generation models
- normalize `choices[0].message.images`

Important boundary:

- OpenRouter should not be treated as a full OpenAI Responses implementation
- built-in tool support should default to conservative behavior

### Gemini

Implement Gemini via native APIs instead of OpenAI emulation.

Text path:

- `responses` -> `generateContent` and streaming equivalent

Image path:

- `images.generate` -> Gemini image-generation or prediction path

Key adaptation work:

- content-part formatting
- function declarations / tool configuration
- structured output schema conversion
- thought / reasoning metadata mapping

### Anthropic

Implement Anthropic via `v1/messages`.

Text path:

- `responses` -> Anthropic Messages API

Initial image path:

- no direct `images.generate` implementation unless a stable Anthropic image
  generation API is deliberately adopted later

Key adaptation work:

- system-message normalization
- content blocks
- tool use / tool result blocks
- thinking budget mapping
- structured output configuration

### Volcengine

Do not fully implement Volcengine in the first pass, but preserve a clean
adapter slot:

- `responses` -> native Volcengine responses family
- `images.generate` -> native Volcengine image API

The planner and profiles should be ready for this without further public API
changes.

## Borrowed Ideas From `ruby_llm`

The `ruby_llm` reference validates several choices that this design should
reuse in principle:

1. provider base plus provider-specific submodules
2. capability-aware model metadata
3. OpenRouter image generation via chat-completions
4. native Gemini and Anthropic protocol adapters instead of forcing them into
   OpenAI wire shapes

What should *not* be copied directly:

- the single verb-centric provider API (`complete`, `paint`, `embed`)
- heuristic capability guessing as the primary truth source
- a broad public surface we do not need for this project

## Core Matrix Migration

### 1. Stop Routing By `wire_api` In Business Logic

`core_matrix` should stop branching in request dispatch based on:

- `chat_completions`
- `responses`

Instead it should branch by intent and capability:

- text / tool / multimodal generation -> `client.responses.*`
- image generation -> `client.images.generate`

`wire_api` can remain as transport metadata but should no longer be the primary
business abstraction.

### 2. Normalize Capability Snapshots

`ProviderRequestContext` should include a normalized capability snapshot built
from catalog data.

`core_matrix` should not infer model support from provider family or model name
when the catalog already states the answer.

Important baseline distinction:

- catalog validation already knows about a limited capability schema
- runtime request dispatch does not yet consume that schema directly
- this migration therefore requires both context-shape expansion and dispatch
  rewiring; it is not just a call-site cleanup

### 3. Expand Catalog Capabilities

Recommended additions to `llm_catalog.yml` model capability schema:

- `image_generation`
- `streaming`
- `conversation_state`
- `provider_builtin_tools`

Likely companion additions:

- resource-level routing hints where provider-level `wire_api` is too coarse
- explicit image-generation capability or provider-family metadata for image
  models that should not inherit text defaults

This is especially important for:

- Gemini text models
- Gemini image models such as Banana Pro or related future selectors
- Anthropic automation-focused models such as Claude Opus variants

### 4. Replace Structural Result Detection

`NormalizeProviderResponse` should stop using structure checks such as
`respond_to?(:output_items)` to decide how to normalize provider results.

Preferred direction:

- normalize `Responses::Result` explicitly
- normalize `Images::Result` explicitly
- make the result class part of the contract rather than an incidental shape

## Error Model

The planner should reject impossible requests before transport dispatch.

Examples:

- image input requested for a model with `multimodal_inputs.image == false`
- built-in tools requested while `provider_builtin_tools == false`
- image generation requested for a model with `image_generation == false`
- response-state chaining requested while `conversation_state == false`

Recommended error categories:

- `SimpleInference::CapabilityError`
- `SimpleInference::ValidationError`
- `SimpleInference::HTTPError`
- `SimpleInference::ConnectionError`
- `SimpleInference::TimeoutError`
- `SimpleInference::DecodeError`

## Streaming Design Notes

Streaming must stay compatible with modern Ruby scheduling and avoid forcing
buffer-all behavior.

Requirements:

- transport remains chunk-yielding and scheduler-friendly
- adapters may expose provider-specific event sequencing internally
- public streams should provide stable high-level events plus raw payload access
- final normalized result must be obtainable after the stream completes

Provider-specific event richness should be additive, not required for basic use.

## Testing Strategy

### `simple_inference`

Use TDD for all new public-resource behavior.

Test layers:

1. resource contract tests
2. request planner capability tests
3. protocol adapter payload / parsing tests
4. stream aggregation tests
5. image normalization tests

Minimum provider coverage in the first pass:

- OpenAI responses
- OpenAI images
- OpenRouter image generation
- Gemini responses
- Anthropic responses

### `core_matrix`

Add focused tests for:

1. catalog capability parsing
2. capability-gated request dispatch
3. normalized response result handling
4. image-generation request routing
5. MockLLM responses and image endpoints using the new canonical wire shapes

Execution requirement for this rollout:

- run the full `core_matrix` verification suite
- run `bundle exec rake` in `core_matrix/vendor/simple_inference`
- run `ACTIVE_ACCEPTANCE_ENABLE_2048_CAPSTONE=1 bash acceptance/bin/run_active_suite.sh`
  from the repo root before claiming completion

This is stricter than the minimum design requirement because the approved
execution scope explicitly includes end-to-end validation and acceptance
coverage.

## Migration Sequence

Recommended order:

1. expand catalog capability schema and request-context shape
2. add new capability / profile objects
3. add resource objects and normalized result classes
4. move current OpenAI responses implementation under the new resource contract
5. add a real MockLLM `responses` endpoint and align mock streaming to the
   modern Responses shape
6. add OpenAI images support
7. add OpenRouter image generation support
8. add Gemini responses support
9. add Anthropic responses support
10. migrate `core_matrix` dispatch and normalization to the new resource API
11. update MockLLM and test helpers for the new canonical request and response
    shapes, including multimodal inputs where covered
12. delete old helper-oriented entry points

## Decision Summary

This design chooses:

- resource-oriented public APIs
- capability-driven request planning
- OpenAI semantics as canonical for OpenAI-standard paths
- native Gemini and Anthropic adapters instead of OpenAI-shape emulation
- explicit request-time gates for built-in tools and multimodal behavior
- `core_matrix` migration away from `wire_api` as the primary abstraction

This should make later support for:

- Gemini text and image models
- Anthropic automation-oriented models
- Volcengine native responses and image APIs

materially smoother without another public API redesign.
