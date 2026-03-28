# Workflow Context Assembly And Execution Snapshot

## Purpose

Task 09.4 added the first context-assembly boundary for workflow execution.
Task B1 and the Phase 2 execution-snapshot unification batch split persistent
config ownership from runtime-facing execution-snapshot ownership so workflow
and provider execution stop reopening aggregate models or mixed JSON blobs.

This task does not execute workflow nodes or speak the machine protocol. It
freezes a per-turn execution snapshot that preserves:

- the resolved config payload that should survive retries and follow-up turns
- stable execution identity for agent code
- visible transcript context rows for the current turn path
- active local imports and summary artifacts
- a canonical attachment manifest
- runtime attachment refs and capability-gated model input attachments derived
  from that manifest

## Execution Snapshot Shape

- `Workflows::BuildExecutionSnapshot` is the application-service boundary for
  persisted execution-snapshot assembly.
- `Workflows::CreateForTurn` resolves model selection first, then persists two
  separate turn-owned row contracts:
  - `turns.resolved_config_snapshot`
  - `turns.execution_snapshot_payload`
- `resolved_config_snapshot` preserves only the resolved configuration payload
  for the turn.
- `execution_snapshot_payload` freezes the runtime-facing execution contract.
- `Turn#execution_snapshot` wraps that payload in `TurnExecutionSnapshot`, which
  owns the runtime field readers and `to_h`.
- The persisted execution snapshot currently freezes these top-level fields:
  - `identity`
  - `model_context`
  - `provider_execution`
  - `budget_hints`
  - `turn_origin`
  - `context_messages`
  - `context_imports`
  - `attachment_manifest`
  - `runtime_attachment_manifest`
  - `model_input_attachments`
  - `attachment_diagnostics`

## Identity And Origin

- `identity` carries stable ownership identifiers for agent code:
  - `user_id`
  - `workspace_id`
  - `conversation_id`
  - `turn_id`
  - `execution_environment_id`
  - `agent_deployment_id`
- these identity fields are public ids for the referenced resources, not raw
  internal `bigint` primary keys
- `turn_origin` preserves the current turn's origin kind, origin payload, and
  source reference metadata
- when `turn_origin.source_ref_type` points at an in-scope resource such as
  `User` or `AgentDeployment`, `turn_origin.source_ref_id` is that resource's
  public id rather than its internal row id
- automation-origin turns therefore assemble successfully even when they do not
  have a selected transcript-bearing input message

## Model Context And Budget Hints

- `model_context` freezes provider-qualified model metadata needed by later
  runtime pairing and local provider execution:
  - `provider_handle`
  - `model_ref`
  - `api_model`
  - `wire_api`
  - `transport`
  - `tokenizer_hint`
  - string-keyed provider and model metadata
- `provider_execution` freezes provider-facing request settings separately from
  transcript or attachment context:
  - `wire_api`
  - `execution_settings`
- `execution_settings` are filtered to the current provider wire API instead of
  blindly copying the whole resolved turn config payload
- `ProviderRequestSettingsSchema` is the canonical owner of request-setting
  filtering and validation for both catalog defaults and resolved runtime
  overrides
- for Phase 2 provider-backed execution, merge precedence is:
  1. model catalog `request_defaults`
  2. the turn's resolved config snapshot
- `budget_hints` keeps hard ceilings separate from advisory runtime hints:
  - `hard_limits.context_window_tokens`
  - `hard_limits.max_output_tokens`
  - `advisory_hints.recommended_compaction_threshold`
- `recommended_compaction_threshold` is derived from
  `context_window_tokens * context_soft_limit_ratio` and remains advisory only
- `ProviderExecution::BuildRequestContext` now reads provider/model/budget
  fields from `TurnExecutionSnapshot` instead of reopening aggregate helpers or
  re-deriving request settings from a mixed snapshot blob
- `ProviderExecution::BuildRequestContext` returns a validated
  `ProviderRequestContext`, so request dispatch and persistence stages no
  longer decode provider context out of raw nested hashes
- `Workflows::ExecuteRun` remains a thin workflow-owned caller; its default
  message path reads frozen context messages from the execution snapshot
- provider-backed turn execution now keeps a stable public entrypoint
  (`ProviderExecution::ExecuteTurnStep`) but splits dispatch, freshness
  locking, and terminal persistence into narrower collaborators

## Context Messages And Imports

- `Conversations::TranscriptProjection`,
  `Conversations::ContextProjection`, and
  `Conversations::HistoricalAnchorProjection` are the dedicated read-side
  projection collaborators for transcript and context assembly
- `context_messages` are derived from `Conversations::ContextProjection`, not
  from a global conversation DAG traversal or from aggregate-model helper
  methods
- messages from the current conversation are bounded to the current turn path;
  later same-conversation turns are not pulled into the snapshot
- selected output messages from earlier turns remain part of the assembled
  context when they are present in the current transcript path
- `context_imports` are derived only from the current conversation's persisted
  `ConversationImport` rows
- where imports reference externally meaningful resources such as conversations
  or messages, the snapshot emits those references as public ids
- import rows that do not have their own `public_id` do not leak raw internal
  row ids through the runtime snapshot
- superseded summary segments are skipped so the snapshot retains only current
  imported summary artifacts
- non-transcript `ConversationEvent` rows do not enter canonical context
  assembly by default because the builder reads transcript-bearing messages and
  explicit import rows only

## Attachment Projection

- the canonical attachment store for this task is `attachment_manifest`
- each manifest row freezes:
  - `attachment_id`
  - `source_message_id`
  - `origin_attachment_id` when present
  - `origin_message_id` when present
  - `filename`
  - `content_type`
  - `byte_size`
  - `modality`
  - `runtime_ref`
- attachment and message references inside these payloads are public ids for
  the corresponding resources
- `runtime_attachment_manifest` is a runtime-facing projection derived from the
  frozen manifest
- `model_input_attachments` is the model-facing projection derived from the
  same frozen manifest
- attachment-manifest correctness is defined by membership and frozen metadata;
  attachment ids are not themselves a semantic ordering boundary
- hidden, context-excluded, or branch-ineligible messages never contribute
  attachments because attachment eligibility inherits from the parent message's
  context projection state

## Capability Gating And Diagnostics

- attachment prompt projection is gated by the provider-model choice already
  frozen on the turn by selector resolution
- the builder uses the pinned `resolved_provider_handle` and
  `resolved_model_ref` to read the provider catalog once at assembly time, then
  freezes the resulting projections onto the turn
- supported modalities become `model_input_attachments`
- unsupported modalities still remain in `attachment_manifest` and
  `runtime_attachment_manifest` so runtime tooling can access them
- unsupported prompt projection is recorded explicitly in
  `attachment_diagnostics` with `reason=unsupported_modality`
- if the bound conversation runtime contract disables attachment upload
  entirely, the builder emits empty attachment projections and records
  `attachment_diagnostics` with
  `reason=conversation_attachment_upload_disabled`

## Aggregate And Read-Side Boundaries

- `Turn` keeps aggregate invariants and row ownership only:
  - lifecycle
  - origin metadata and selected-message pointers
  - deployment/environment consistency
  - resolved config snapshot row
  - resolved model-selection snapshot row
  - execution snapshot payload row
- `Turn` exposes one runtime-facing reader: `execution_snapshot`
- `WorkflowRun` delegates runtime-facing snapshot reads through
  `turn.execution_snapshot`
- `Conversation` no longer owns transcript/context projection helpers; the
  projection services under `app/services/conversations/` are the read-side
  owners for transcript, context, and historical-anchor projection logic

## Failure Modes

- snapshot assembly rejects turns that do not yet have a resolved provider/model
  snapshot
- provider execution settings do not leak unrelated resolved config keys such
  as sandbox or other non-provider flags into the outbound provider request
- unsupported attachment modalities are not serialized as if the model saw them
- hidden, excluded, or branch-ineligible attachments do not leak into the
  frozen manifest
- automation turns assemble with empty transcript context rather than failing on
  a missing selected input message

## Rails And Reference Findings

- Local Rails Active Storage guides confirmed the `has_one_attached` access
  pattern used here: attachment rows expose stable blob metadata such as
  filename, content type, and byte size, and those values can be frozen into
  execution snapshots without downloading the file contents
- The same guide also documents `identify: false` when tests or execution paths
  need to suppress content sniffing and rely on the declared content type
- A narrow Dify sanity check on
  `references/original/references/dify/api/models/workflow.py` showed Dify
  injects files into prompt memory through a current `sys.files` variable at
  render time. Core Matrix intentionally freezes a canonical attachment manifest
  onto the executing turn first, then derives runtime refs and model-facing
  blocks from that snapshot so later visibility or capability changes do not
  reinterpret historical executions.
