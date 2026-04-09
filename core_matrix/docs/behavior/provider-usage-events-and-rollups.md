# Provider Usage Events And Rollups

## Purpose

Task 06.1 adds provider usage accounting as an event-truth layer plus projected
rollups. `UsageEvent` is the durable detailed source. `UsageRollup` is a
derived aggregation layer for reporting and future quota or entitlement checks.

Within the lifecycle model:

- `UsageEvent` is `bounded_audit`
- `UsageRollup` is `retained_aggregate`

That means detailed provider usage is not modeled as forever-retained business
truth. The system prunes raw `UsageEvent` rows through retention maintenance
after `DATA_RETENTION_BOUNDED_AUDIT_DAYS`, while rollups remain available for
long-horizon reporting.

## Usage Event Behavior

- `UsageEvent` records one usage fact at a point in time.
- Events can attach to existing installation-owned dimensions that already
  exist in this phase, such as user, workspace, agent program, and agent
  deployment.
- Event rows also preserve nullable generic references for later runtime roots:
  `conversation_id`, `turn_id`, and `workflow_node_key`.
- Provider and model identity are stored as explicit strings on the event.
- Operation kinds cover token and non-token AI work, including text, image,
  video, embeddings, speech, transcription, and future media analysis.
- Token counts and media-unit counts are both supported.
- Current provider-backed `turn_step` execution records authoritative usage from
  the provider response after the workflow step completes.
- Successful provider-backed text generation records:
  - `provider_handle`
  - `model_ref`
  - `operation_kind = text_generation`
  - `conversation_id`
  - `turn_id`
  - `workflow_node_key`
  - provider-returned input and output tokens when available
  - `prompt_cache_status`
  - `cached_input_tokens` when the provider explicitly returns cache detail
  - observed end-to-end latency for the provider call
- `UsageEvent#total_tokens` remains a convenience helper over the stored input
  and output token columns; the durable truth stays in the row itself.
- Prompt-cache semantics are tri-state:
  - `available`
  - `unknown`
  - `unsupported`
- `unknown` means the provider response omitted cache detail; it must not be
  treated as `cached_input_tokens = 0`.
- `unsupported` is only used when provider or model metadata explicitly opts
  out via `usage_capabilities.prompt_cache_details = false`.

## Rollup Behavior

- `UsageRollup` stores derived aggregates only; it is not the sole truth source.
- Rollups are bucketed by:
  - hour
  - day
  - explicit rolling-window identifier
- Rollups preserve the same usage dimensions as the originating event so later
  reporting and quota logic can stay scoped.
- Rollups also project prompt-cache aggregates:
  - `cached_input_tokens_total`
  - `prompt_cache_available_event_count`
  - `prompt_cache_unknown_event_count`
  - `prompt_cache_unsupported_event_count`
- Rollup uniqueness is enforced by installation, bucket, and a dimension digest
  instead of a giant nullable-column unique index.
- Long-horizon reporting should prefer rollups rather than depending on raw
  `UsageEvent` rows remaining forever.

## Projection Behavior

- `ProviderUsage::RecordEvent` creates one `UsageEvent` and immediately projects
  rollups in the same transaction.
- provider-backed `turn_step` execution uses `ProviderUsage::RecordEvent` as
  the authoritative usage write boundary once the node finishes successfully.
- the write happens during `PersistTurnStepSuccess`, after the provider result
  has been accepted for the executing node.
- `ProviderUsage::ProjectRollups` always projects hourly and daily rollups.
- A rolling-window rollup is projected only when the event carries an explicit
  `entitlement_window_key`.
- Re-projecting the same event again increments the same rollup rows; the
  projection service is additive, not idempotent by event identifier.
- `cached_input_tokens_total` sums only `available` events.
- Prompt-cache hit rate is derived, not stored:
  - numerator: `cached_input_tokens_total`
  - denominator: input tokens from `available` events only
  - `unknown` and `unsupported` events are excluded from the denominator
  - when there are no `available` events, hit rate is `null`

## Invariants

- usage events remain the detailed accounting truth
- rollups remain derived performance and reporting rows
- raw usage-event retention is allowed to be shorter than rollup retention
- this task does not hard-couple to future conversation, turn, or workflow
  tables that land later in Milestone 3
- provider/model references are preserved on the event exactly as observed at
  runtime instead of being revalidated against the current live catalog
- authoritative usage remains separate from execution telemetry and threshold
  advice; correlation and advisory evaluation belong in execution facts, not in
  usage rows

## Failure Modes

- cross-installation references for user, workspace, agent program, or
  agent program version are rejected
- negative token, media-unit, latency, or cost values are rejected
- duplicate rollups for the same bucket and dimension digest are rejected
- malformed or missing operation and bucket kinds are rejected

## Reference Sanity Check

The retained conclusion from the OpenClaw usage-report reference is narrow:
aggregated reports should be projections over detailed usage facts, not the
only durable source.

Core Matrix keeps that same event-truth-versus-rollup separation, but stores
the detailed facts in relational usage-event rows instead of deriving reports
from ad hoc log files.
