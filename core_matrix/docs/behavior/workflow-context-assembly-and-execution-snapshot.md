# Workflow Context Assembly And Execution Snapshot

## Purpose

Task 09.4 adds the first context-assembly boundary for workflow execution.

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

- `Workflows::ContextAssembler` is the application-service boundary for v1
  execution snapshot assembly.
- `Workflows::CreateForTurn` now resolves model selection first, then replaces
  `Turn.resolved_config_snapshot` with a wrapped execution snapshot:
  - `config`
  - `execution_context`
- `config` preserves the effective resolved configuration payload for the turn.
- `execution_context` currently freezes:
  - `identity`
  - `turn_origin`
  - `context_messages`
  - `context_imports`
  - `attachment_manifest`
  - `runtime_attachment_manifest`
  - `model_input_attachments`
  - `attachment_diagnostics`

## Identity And Origin

- `execution_context.identity` carries stable ownership identifiers for agent
  code:
  - `user_id`
  - `workspace_id`
  - `conversation_id`
  - `turn_id`
  - `agent_deployment_id`
- `execution_context.turn_origin` preserves the current turn's origin kind,
  origin payload, and source reference metadata.
- Automation-origin turns therefore assemble successfully even when they do not
  have a selected transcript-bearing input message.

## Context Messages And Imports

- `context_messages` are derived from
  `Conversation#context_projection_messages`, not from a global conversation DAG
  traversal.
- Messages from the current conversation are bounded to the current turn path;
  later same-conversation turns are not pulled into the snapshot.
- Selected output messages from earlier turns remain part of the assembled
  context when they are present in the current transcript path.
- `context_imports` are derived only from the current conversation's persisted
  `ConversationImport` rows.
- Superseded summary segments are skipped so the snapshot retains only current
  imported summary artifacts.
- Non-transcript `ConversationEvent` rows do not enter canonical context
  assembly by default because the assembler reads transcript-bearing messages
  and explicit import rows only.

## Attachment Projection

- The canonical attachment store for this task is `attachment_manifest`.
- Each manifest row freezes:
  - `attachment_id`
  - `source_message_id`
  - `origin_attachment_id` when present
  - `origin_message_id` when present
  - `filename`
  - `content_type`
  - `byte_size`
  - `modality`
  - `runtime_ref`
- `runtime_attachment_manifest` is a runtime-facing projection derived from the
  frozen manifest.
- `model_input_attachments` is the model-facing projection derived from the
  same frozen manifest.
- Attachment-manifest correctness is defined by membership and frozen metadata;
  attachment ids are not themselves a semantic ordering boundary.
- Hidden, context-excluded, or branch-ineligible messages never contribute
  attachments because attachment eligibility inherits from the parent message's
  context projection state.

## Capability Gating And Diagnostics

- Attachment prompt projection is gated by the provider-model choice already
  frozen on the turn by Task 09.3.
- The assembler uses the pinned `resolved_provider_handle` and
  `resolved_model_ref` to read the current provider catalog once at assembly
  time, then freezes the resulting projections onto the turn.
- Supported modalities become `model_input_attachments`.
- Unsupported modalities still remain in `attachment_manifest` and
  `runtime_attachment_manifest` so runtime tooling can access them.
- Unsupported prompt projection is recorded explicitly in
  `attachment_diagnostics` with `reason=unsupported_modality`.

## Turn And Workflow Helpers

- `Turn` now exposes read helpers for:
  - `effective_config_snapshot`
  - `execution_identity`
  - `turn_origin_context`
  - `context_messages`
  - `context_imports`
  - `attachment_manifest`
  - `runtime_attachment_manifest`
  - `model_input_attachments`
  - `attachment_diagnostics`
- `WorkflowRun` delegates the execution-identity and attachment-projection
  helpers to its owning turn so operational queries do not need to reopen the
  raw JSON payload.

## Failure Modes

- context assembly rejects turns that do not yet have a resolved provider/model
  snapshot
- unsupported attachment modalities are not serialized as if the model saw them
- hidden, excluded, or branch-ineligible attachments do not leak into the
  frozen manifest
- automation turns assemble with empty transcript context rather than failing on
  a missing selected input message

## Rails And Reference Findings

- Local Rails Active Storage guides confirmed the `has_one_attached` access
  pattern used here: attachment rows expose stable blob metadata such as
  filename, content type, and byte size, and those values can be frozen into
  execution snapshots without downloading the file contents.
- The same guide also documents `identify: false` when tests or execution paths
  need to suppress content sniffing and rely on the declared content type.
- A narrow Dify sanity check on
  `references/original/references/dify/api/models/workflow.py` showed Dify
  injects files into prompt memory through a current `sys.files` variable at
  render time. Core Matrix intentionally freezes a canonical attachment manifest
  onto the executing turn first, then derives runtime refs and model-facing
  blocks from that snapshot so later visibility or capability changes do not
  reinterpret historical executions.
