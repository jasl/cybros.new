# Workflow Context Assembly And Execution Snapshot

## Purpose

Task 09.4 added the first context-assembly boundary for workflow execution.
Task B1 and the later execution-snapshot unification batch split persistent
config ownership from runtime-facing execution-snapshot ownership so workflow
and provider execution stop reopening aggregate models or mixed JSON blobs.

This task does not execute workflow nodes or speak the machine protocol. It
freezes a per-turn execution snapshot that preserves:

- the resolved config payload that should survive retries and follow-up turns
- stable execution identity for agent code
- visible transcript context rows for the current turn path
- active local imports and summary artifacts
- a canonical attachment manifest
- provider-facing model input attachments derived from that manifest
- attachment diagnostics for provider projection only; execution-runtime
  attachment access remains on-demand

## Execution Snapshot Shape

- `Workflows::BuildExecutionSnapshot` is the application-service boundary for
  persisted execution-snapshot assembly.
- `Workflows::CreateForTurn` resolves model selection first, then persists two
  separate turn-owned row contracts:
  - `turns.resolved_config_snapshot`
  - `execution_contracts`
- `resolved_config_snapshot` preserves only the resolved configuration payload
  for the turn.
- `ExecutionContract` freezes the runtime-facing execution contract while
  `ExecutionCapabilitySnapshot` and `ExecutionContextSnapshot` hold the
  deduplicated capability surface and visible context membership.
- `Turn#execution_snapshot` wraps that payload in `TurnExecutionSnapshot`, which
  owns the runtime field readers and `to_h`.
- The persisted execution snapshot currently freezes these top-level fields:
  - `identity`
  - `task`
  - `conversation_projection`
  - `capability_projection`
  - `provider_context`
  - `runtime_context`
  - `turn_origin`
  - `attachment_manifest`
  - `model_input_attachments`
  - `attachment_diagnostics`

## Identity And Origin

- `identity` carries stable ownership identifiers for agent code:
  - `user_id`
  - `workspace_id`
  - `conversation_id`
  - `turn_id`
  - `executor_program_id`
  - `agent_program_version_id`
- these identity fields are public ids for the referenced resources, not raw
  internal `bigint` primary keys
- `turn_origin` preserves the current turn's origin kind, origin payload, and
  source reference metadata
- when `turn_origin.source_ref_type` points at an in-scope resource such as
  `User` or `AgentProgramVersion`, `turn_origin.source_ref_id` is that resource's
  public id rather than its internal row id
- automation-origin turns therefore assemble successfully even when they do not
  have a selected transcript-bearing input message

## Task, Provider Context, And Budget Hints

- `task` freezes the runtime work identity that was previously split across
  mailbox payload extras:
  - `conversation_id`
  - `turn_id`
  - selected-message ids when present
  - origin/source reference metadata needed by downstream runtime code
- `provider_context` freezes provider-qualified model metadata and loop
  settings needed by later runtime pairing and local provider execution:
  - `budget_hints`
  - `provider_execution`
  - `model_context`

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
- for current provider-backed execution, merge precedence is:
  1. model catalog `request_defaults`
  2. the turn's resolved config snapshot
- `budget_hints` keeps hard ceilings separate from advisory runtime hints:
  - `hard_limits.context_window_tokens`
  - `hard_limits.max_output_tokens`
  - `advisory_hints.recommended_compaction_threshold`
- `recommended_compaction_threshold` is derived from
  `context_window_tokens * context_soft_limit_ratio` and remains advisory only
- `ProviderExecution::BuildRequestContext` now reads provider/model/budget
  fields from `TurnExecutionSnapshot#provider_context` instead of reopening
  aggregate helpers or re-deriving request settings from a mixed snapshot blob
- `ProviderExecution::BuildRequestContext` returns a validated
  `ProviderRequestContext`, so request dispatch and persistence stages no
  longer decode provider context out of raw nested hashes
- `Workflows::ExecuteRun` is the enqueue boundary for one runnable
  `turn_step` node, not the provider execution body itself
- `Workflows::ExecuteNode` and `ProviderExecution::ExecuteTurnStep` read frozen
  conversation messages from `execution_snapshot.conversation_projection` when
  the caller does not override messages
- provider-backed turn execution now keeps a stable public entrypoint
  (`ProviderExecution::ExecuteTurnStep`) but splits dispatch, freshness
  locking, and terminal persistence into narrower collaborators

## Capability Projection

- `capability_projection` freezes the runtime-owned execution metadata that
  agent programs consume directly:
  - `tool_surface`
  - `profile_key`
  - `is_subagent`
  - `subagent_session_id`
  - `parent_subagent_session_id`
  - `subagent_depth`
  - `owner_conversation_id`
  - `subagent_policy`
- `profile_key` is resolved from the runtime-declared `profile_catalog` before
  the turn executes
- `tool_surface` is the conversation-visible tool catalog for that turn and
  must be treated as an execution-time constraint, not as advisory trace data
- `Workflows::BuildExecutionSnapshot` composes that turn capability surface
  through `RuntimeCapabilities::ComposeForTurn`
- mailbox execution assignment creation copies `capability_projection` from
  the frozen execution snapshot rather than recomputing it later from mutable
  aggregates

## Conversation Projection And Imports

- `Conversations::TranscriptProjection`,
  `Conversations::ContextProjection`, and
  `Conversations::HistoricalAnchorProjection` are the dedicated read-side
  projection collaborators for transcript and context assembly
- `conversation_projection.messages` are derived from
  `Conversations::ContextProjection`, not from a global conversation DAG
  traversal or from aggregate-model helper methods
- messages from the current conversation are bounded to the current turn path;
  later same-conversation turns are not pulled into the snapshot
- selected output messages from earlier turns remain part of the assembled
  context when they are present in the current transcript path
- `conversation_projection.context_imports` are derived only from the current
  conversation's persisted `ConversationImport` rows
- `conversation_projection.prior_tool_results` starts empty at snapshot time
  and is later filled by provider-round preparation when earlier tool nodes are
  part of the current round continuation
- `conversation_projection.projection_fingerprint` is a deterministic digest of
  the visible message and import projection used for downstream traceability
- where imports reference externally meaningful resources such as conversations
  or messages, the snapshot emits those references as public ids
- import rows that do not have their own `public_id` do not leak raw internal
  row ids through the runtime snapshot
- superseded summary segments are skipped so the snapshot retains only current
  imported summary artifacts
- non-transcript `ConversationEvent` rows do not enter canonical context
  assembly by default because the builder reads transcript-bearing messages and
  explicit import rows only

## Program Wire Contract

- the frozen `execution_snapshot` remains the canonical turn-owned contract
  inside Core Matrix
- the program runtime does not receive that contract verbatim
- `prepare_round` now projects only the compact fields the external runtime
  actually consumes:
  - `round_context.messages`
  - `round_context.context_imports`
  - `round_context.projection_fingerprint`
  - `agent_context.profile`
  - `agent_context.is_subagent`
  - `agent_context.subagent_session_id`
  - `agent_context.parent_subagent_session_id`
  - `agent_context.subagent_depth`
  - `agent_context.owner_conversation_id`
  - `agent_context.allowed_tool_names`
  - `provider_context`
  - `runtime_context`
- `prepare_round` does not carry `prior_tool_results`; prior tool results are
  appended later by Core Matrix when it materializes the next provider request
- `execute_program_tool` also uses compact `agent_context` instead of shipping
  the full frozen `tool_surface`
- `prepare_round` responses now return `visible_tool_names` instead of a full
  repeated `tool_surface` schema array
- Core Matrix maps `visible_tool_names` back onto the canonical frozen
  `capability_projection.tool_surface` when it needs concrete tool schemas for
  provider dispatch
- this split is intentional:
  - the database still freezes the full execution contract once
  - the wire contract sends only the minimal runtime projection needed for the
    current protocol step

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
- attachment and message references inside these payloads are public ids for
  the corresponding resources
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
- unsupported modalities still remain in `attachment_manifest` so execution
  tooling can access them later through an authenticated request
- unsupported prompt projection is recorded explicitly in
  `attachment_diagnostics` with `reason=unsupported_modality`
- execution-runtime attachment delivery is not precomputed into the snapshot
- execution tooling must request concrete attachment handles through
  `POST /executor_api/attachments/request`

## Aggregate And Read-Side Boundaries

- `Turn` keeps aggregate invariants and row ownership only:
  - lifecycle
  - origin metadata and selected-message pointers
  - frozen agent-program-version / execution-runtime identity
  - resolved config snapshot row
  - resolved model-selection snapshot row
  - execution contract pointer
- `Turn` exposes one runtime-facing reader: `execution_snapshot`
- `WorkflowRun` delegates runtime-facing snapshot reads through
  `turn.execution_snapshot`
- transcript, context, and historical-anchor projection logic lives in the
  projection services under `app/services/conversations/`, not on
  `Conversation` itself
- `Conversation` does not own runtime-contract assembly; services that need
  runtime capabilities must compose them from the frozen turn

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
