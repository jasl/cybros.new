# Provider Usage Prompt Cache Metrics Design

## Goal

Make prompt cache telemetry a first-class part of the existing provider usage
domain in `core_matrix`, with:

- per-request persistence of cache support state and cached input tokens
- diagnostics aggregation that distinguishes `0` from `unknown`
- debug export visibility for raw events and aggregated cache metrics
- compatibility with OpenAI-compatible providers that omit cache detail fields

This design intentionally does not add workflow-node duration metrics or turn
total duration metrics. Those remain a separate follow-up because they belong
to execution lifecycle modeling rather than provider usage accounting.

## Why This Exists

CoreMatrix already records durable provider usage and exposes conversation/turn
diagnostics, but the current pipeline collapses provider usage into:

- `input_tokens`
- `output_tokens`
- `total_tokens`
- `latency_ms`

That loses prompt cache detail before it reaches durable storage or client
surfaces. Today:

- the provider dispatch and normalization paths only keep the three token
  totals
- `usage_events` and `usage_rollups` have no cache-specific columns
- diagnostics can show latency and token totals, but cannot tell whether a
  prompt cache miss happened, whether the provider omitted the metric, or
  whether the provider does not support the metric at all

If CoreMatrix is going to show prompt cache behavior, it must preserve those
states explicitly. Treating a missing cache metric as `0` would be
product-incorrect.

## Design Principles

### 1. Prompt cache telemetry belongs to provider usage, not execution profiling

Prompt cache hits affect provider-side token accounting and billing semantics.
They should stay inside the `UsageEvent` / `UsageRollup` domain rather than be
attached to `ExecutionProfileFact`.

### 2. Missing is not zero

The system must keep the difference between:

- provider returned cache detail and it was `0`
- provider returned no cache detail for this request
- provider is explicitly known not to support this metric

Any aggregation that collapses those states into one bucket is wrong.

### 3. Aggregations must operate only on supported samples

Prompt cache hit rate should be computed only over events where the provider
explicitly returned cache telemetry. Unsupported or unknown samples should be
reported separately and excluded from the ratio denominator.

### 4. Diagnostics should stay compact, but debug export should stay forensic

Conversation and turn diagnostics should expose compact aggregate fields. Debug
export should expose both aggregate fields and raw event-level prompt cache
state so operators can inspect why a ratio is missing or lower than expected.

## Target Data Model

Extend `usage_events` with:

- `prompt_cache_status :string, null: false, default: "unknown"`
- `cached_input_tokens :integer`

Supported `prompt_cache_status` values:

- `available`
- `unknown`
- `unsupported`

Validation rules:

- `cached_input_tokens` must be non-negative when present
- `cached_input_tokens` must be present or zero-allowed when
  `prompt_cache_status == "available"`
- `cached_input_tokens` must be `nil` when status is `unknown` or
  `unsupported`

Extend `usage_rollups` with:

- `cached_input_tokens_total :integer, null: false, default: 0`
- `prompt_cache_available_event_count :integer, null: false, default: 0`
- `prompt_cache_unknown_event_count :integer, null: false, default: 0`
- `prompt_cache_unsupported_event_count :integer, null: false, default: 0`

Extend `turn_diagnostics_snapshots` and
`conversation_diagnostics_snapshots` with:

- `cached_input_tokens_total :integer, null: false, default: 0`
- `prompt_cache_available_event_count :integer, null: false, default: 0`
- `prompt_cache_unknown_event_count :integer, null: false, default: 0`
- `prompt_cache_unsupported_event_count :integer, null: false, default: 0`

No snapshot table should persist a pre-rounded `prompt_cache_hit_rate`. The
rate should be derived from the snapshot totals when serializing or
recomputing.

## Prompt Cache Semantics

### Event-level semantics

For one usage event:

- `available`
  - provider returned cache detail for this request
  - `cached_input_tokens` is persisted
  - `cached_input_tokens` may be `0`
- `unknown`
  - the request completed and usage exists, but no cache detail was returned
  - no ratio should be inferred
- `unsupported`
  - CoreMatrix explicitly knows this provider/wire-api combination does not
    expose cache detail
  - this should be used only when catalog/config metadata declares it, not as a
    guess

### Aggregate semantics

For any aggregate:

- `cached_input_tokens_total`
  - sum of `cached_input_tokens` only across `available` events
- `prompt_cache_available_event_count`
  - count of `available` events
- `prompt_cache_unknown_event_count`
  - count of `unknown` events
- `prompt_cache_unsupported_event_count`
  - count of `unsupported` events
- `prompt_cache_hit_rate`
  - `cached_input_tokens_total / input_tokens_total_for_available_events`
  - `null` when no `available` events exist

This means a provider can appear in diagnostics with:

- `prompt_cache_hit_rate = 0.0`
  - explicit support, no cached tokens used
- `prompt_cache_hit_rate = null`
  - no supported samples

That distinction is the entire point of the design.

## Extraction Rules

Create one canonical normalization path for provider usage. It should return a
compact hash containing:

- `input_tokens`
- `output_tokens`
- `total_tokens`
- `prompt_cache_status`
- `cached_input_tokens`

Extraction rules:

1. Read the raw provider `usage` hash.
2. Extract the existing input/output/total token fields.
3. Look for cache detail in provider-specific nested usage fields, including
   OpenAI-compatible `prompt_tokens_details.cached_tokens` and
   Responses-style equivalents when present.
4. If cache detail is found, emit:
   - `prompt_cache_status = "available"`
   - `cached_input_tokens = extracted value`
5. If cache detail is not found:
   - emit `unsupported` only when provider catalog metadata explicitly marks
     cache detail unsupported
   - otherwise emit `unknown`

This logic should live in one provider-usage normalization helper shared by:

- provider execution dispatch
- provider execution persistence
- provider gateway dispatch
- provider response normalization where diagnostics/debug surfaces include usage

Duplicated inline `normalize_usage` helpers should be removed or reduced to
delegations to that canonical helper.

## Layering

Use this layer split:

- Presentation layer:
  - `AppAPI::ConversationDiagnosticsController`
  - debug export payload builders
- Application layer:
  - provider execution services
  - provider usage event/rollup projection services
  - diagnostics recompute services
- Domain layer:
  - `UsageEvent`
  - `UsageRollup`
  - snapshot models and prompt-cache helper methods
- Infrastructure layer:
  - Active Record schema
  - provider protocol adapters and usage extraction

Provider compatibility knowledge belongs in configuration/catalog metadata and
provider usage normalization, not in controllers.

## Diagnostics Output Shape

Add the following top-level fields to both conversation-level and turn-level
diagnostics responses:

- `cached_input_tokens_total`
- `prompt_cache_available_event_count`
- `prompt_cache_unknown_event_count`
- `prompt_cache_unsupported_event_count`
- `prompt_cache_hit_rate`

`prompt_cache_hit_rate` should be serialized as:

- a decimal string or rounded numeric value when available
- `null` when no supported samples exist

Current UI guidance:

- show the metric only when `prompt_cache_hit_rate` is not `null`
- hide it otherwise

That keeps the API explicit without forcing a product commitment to show
“unknown” immediately.

## Debug Export Output Shape

Extend debug export in two places:

1. Raw `usage_events` items:
   - `prompt_cache_status`
   - `cached_input_tokens`
2. Diagnostics snapshots:
   - all aggregate prompt cache fields listed above

This keeps operator debugging possible even if the normal UI hides unknown or
unsupported states.

## Provider Catalog Compatibility

No provider should be hard-coded as unsupported in application services.
Instead, support an optional provider/model capability hint in catalog metadata
such as:

- `usage_capabilities.prompt_cache_details = false`

If the hint is absent, CoreMatrix should default to `unknown` when no cache
detail is returned. This preserves forward compatibility with providers that
may add support later.

## Out of Scope

This design does not implement:

- workflow-node `duration_ms`
- turn total elapsed duration
- runtime event protocol changes for real-time prompt cache reporting
- generic raw usage JSON persistence

Those are separate concerns. Prompt cache metrics should land first as a clean
extension of the existing provider usage domain.

## Testing Strategy

Required test coverage:

- usage normalization from chat-completions payloads with cached token detail
- usage normalization from responses payloads with cached token detail
- explicit `cached_input_tokens = 0`
- missing cache detail yielding `unknown`
- explicit unsupported provider metadata yielding `unsupported`
- usage rollup projection of all new counters/totals
- turn diagnostics aggregation excluding unknown/unsupported events from the hit
  rate denominator
- conversation diagnostics aggregation across mixed provider states
- debug export serialization of raw and aggregate prompt cache fields

## Expected Outcome

After this design is implemented, CoreMatrix will be able to answer:

- how many cached input tokens were used for a turn or conversation
- whether a `0%` cache hit rate is real or just unknown
- which providers are returning usable cache telemetry

without conflating provider usage accounting with execution profiling.
