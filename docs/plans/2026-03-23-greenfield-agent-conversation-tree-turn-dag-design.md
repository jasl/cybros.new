# Greenfield Agent Architecture Design

## Status

Target backend/domain architecture for implementing the agent system inside `core_matrix`.

This document is intentionally **not** constrained by the current Cybros schema, migration history, DAG facades, or compatibility requirements. It preserves the product/runtime capabilities that matter while limiting the current implementation slice to backend and domain work. UI, controllers, Action Cable, background job orchestration, and runtime adapter follow-up work are deferred to [CoreMatrix Agent UI And Runtime Follow-Up](./2026-03-23-core-matrix-agent-ui-runtime-follow-up.md).

It only preserves the product/runtime capabilities that matter:

- tree-shaped conversation navigation
- branch from historical messages
- reusable attachments
- per-turn tool loop
- concurrent tool execution
- subagent orchestration and management
- turn-scoped command execution with live output
- approvals, leases, timeouts, and stop semantics
- context compaction and summary imports
- swipe / rerun / retry / edit style version workflows
- bounded, auditable execution history

## Executive Summary

The recommended architecture is:

- **Conversation Tree**
  - user-visible conversation hierarchy
  - optimized for tree navigation, branch browsing, and inherited read-only prefixes
- **Append-Only Transcript**
  - user/system/developer/assistant/character/summary messages live here
  - transcript is not a DAG
- **Per-Turn Workflow DAG**
  - each turn owns a small workflow graph
  - only this layer models concurrency, dependencies, joins, approvals, leases, and failure propagation
- **Workflow-Owned Resources**
  - subagents, shell commands, background processes, artifacts, and event streams are execution resources, not transcript messages
- **Imports Instead Of Global History Merge**
  - branch prefixes, merge summaries, and quoted context are modeled as imports
  - no global conversation-spanning DAG

This design keeps the value of DAG where it matters, while removing the overhead of modeling the entire conversation history as one graph.

## Goals

- keep the user-visible conversation model easy to query and easy to explain
- make tool concurrency and subagent concurrency first-class
- make joins explicit and auditable
- keep transcript truth separate from execution truth
- support efficient tree navigation in the UI without recursive N+1 query patterns
- keep Active Record models clean and explicit
- minimize graph-wide locks and graph-wide traversal
- prefer append-only data and pointer selection over destructive rewrites

## Non-Goals

- no global conversation DAG
- no generic tree gem as the domain source of truth
- no nested-set tree model
- no hidden background work that can outlive its owner turn unless explicitly modeled as a background service
- no child transcript directly mutating parent transcript
- no transcript merge that rewrites historical conversation structure

## Implementation Defaults For V1

These choices are now intentionally fixed so implementation can proceed without another architecture pass.

- use string-backed Rails enums, not PostgreSQL enum types
- use closure-table rows for conversation tree queries
- use plain UUID `public_id` strings in v1; do not block implementation on UUIDv7/ULID work
- use `has_one_attached` for attachment-bearing rows in the Rails implementation
- allow only one active `TurnWorkflow` per conversation at a time
- allow only one open `ApprovalRequest` per workflow node at a time
- support only `all_required` and `best_effort` join policies in v1
- support only serial planner loops at the decision layer
- forbid nested subagent spawn in v1
- keep background services first-class, but ship only start/list/stop/reconcile in v1
- do not ship a user-facing transcript merge UI in v1; keep `merge_summary` imports internal/admin driven first

## Transaction And Lock Boundaries

Implementation should respect these boundaries from day one.

- `Conversations::CreateRoot` and `Conversations::CreateBranch` lock only the parent conversation row while inserting the new conversation and closure rows
- `Turns::StartUserTurn`, `Turns::QueueFollowUp`, and `Turns::SteerCurrentInput` lock only the conversation row
- `Workflows::Mutator` locks one `turn_workflows` row, never the whole conversation tree
- workflow node claiming should use one row-level update on `workflow_nodes` plus lease timestamps
- resource rows are created in `starting` state inside the workflow transaction
- OS process spawn and subagent launch happen after commit, then update the resource row to `running`

This avoids graph-wide locks and makes orphan recovery explicit.

## Layered Rails Shape

This design assumes four layers.

- **Presentation**
  - deferred in the current backend-only slice
  - see the follow-up document for controllers, channels, views/components, and serializers/presenters
- **Application**
  - service objects
  - command handlers
  - query objects
  - reducers
  - context assembly
- **Domain**
  - conversation tree models
  - transcript models
  - workflow models
  - resource models
  - value objects and state rules
- **Infrastructure**
  - Active Record persistence
  - Active Storage
  - job runners
  - OS process management
  - external agent runtimes

Lower layers must not depend on higher layers.

## Core Domain Model

### 1. Conversation Tree

The top-level product model is a tree of conversations.

- a root conversation starts a tree
- a child conversation is created by branching from a historical message or turn in another conversation
- the tree is for navigation, branch browsing, ownership, and inherited prefix resolution
- the tree is **not** the execution graph

### 2. Transcript

Each conversation contains append-only turns and messages.

- turns are ordered within a conversation
- messages belong to turns
- selected input/output pointers determine the canonical visible variant for a turn
- old variants remain immutable and auditable

### 3. Turn Workflow

Each turn owns exactly one workflow.

- the workflow is the only DAG aggregate root
- the workflow is small, local, and bounded to one turn
- it models:
  - model planning steps
  - tool calls
  - command execution
  - subagent runs
  - join / reducer nodes
  - approval gates
  - finalize

### 4. Workflow Resources

Resources are execution-owned durable records.

- subagent runs
- process runs
- workflow artifacts
- workflow events
- approval requests

These are not transcript messages.

## Primary Key Strategy

For a greenfield Rails app optimized for PostgreSQL efficiency, prefer:

- internal primary keys: `bigint`
- external/public references: `public_id`

Use `public_id` on externally addressable records such as:

- conversations
- turns
- messages
- workflows
- workflow nodes
- subagent runs
- process runs

Implementation default:

- use plain UUID strings for `public_id` in v1
- keep internal joins and foreign keys on `bigint`
- revisit UUIDv7 or ULID only if external sortability becomes a real requirement

This keeps indexes and joins small while preserving stable external identifiers.

## Rails Models And Tables

## Conversation Tree Models

### `Conversation`

Purpose:

- user-visible conversation container
- branch root for transcript and turns
- anchor point for tree navigation and imports

Suggested columns:

- `id :bigint`
- `public_id :string, null: false`
- `agent_id :bigint, null: false`
- `title :string, null: false`
- `status :string, null: false`
- `parent_conversation_id :bigint`
- `root_conversation_id :bigint`
- `branched_from_message_id :bigint`
- `branched_from_turn_id :bigint`
- `depth :integer, null: false, default: 0`
- `branch_position :integer, null: false, default: 0`
- `children_count :integer, null: false, default: 0`
- `latest_turn_id :bigint`
- `latest_message_id :bigint`
- `latest_activity_at :datetime`
- `managed_by_subagent_run_id :bigint`
- `metadata :jsonb, null: false, default: {}`
- timestamps

Status enum:

- `active`
- `archived`
- `closed`

Associations:

- `belongs_to :agent`
- `belongs_to :parent_conversation, class_name: "Conversation", optional: true`
- `belongs_to :root_conversation, class_name: "Conversation", optional: true`
- `belongs_to :branched_from_message, class_name: "ConversationMessage", optional: true`
- `belongs_to :branched_from_turn, class_name: "ConversationTurn", optional: true`
- `belongs_to :latest_turn, class_name: "ConversationTurn", optional: true`
- `belongs_to :latest_message, class_name: "ConversationMessage", optional: true`
- `belongs_to :managed_by_subagent_run, class_name: "SubagentRun", optional: true`
- `has_many :child_conversations, class_name: "Conversation", foreign_key: :parent_conversation_id`
- `has_many :turns, class_name: "ConversationTurn", dependent: :destroy`
- `has_many :messages, class_name: "ConversationMessage", dependent: :destroy`
- `has_many :imports, class_name: "ConversationImport", dependent: :destroy`
- `has_many :summary_segments, class_name: "ConversationSummarySegment", dependent: :destroy`

Indexes:

- unique `public_id`
- `agent_id, latest_activity_at`
- `parent_conversation_id, branch_position`
- `root_conversation_id, latest_activity_at`
- `managed_by_subagent_run_id`

Implementation note:

- `root_conversation_id` should be nullable at the database level in v1 because root conversations must be inserted before they can point at themselves
- `Conversations::CreateRoot` should create the row, then immediately set `root_conversation_id = id` in the same transaction

### `ConversationClosure`

Purpose:

- tree projection for efficient ancestors / descendants / breadcrumb / subtree queries
- replaces the need for a tree gem as the primary query mechanism

Suggested columns:

- `ancestor_conversation_id :bigint, null: false`
- `descendant_conversation_id :bigint, null: false`
- `depth :integer, null: false`
- timestamps optional

Associations:

- `belongs_to :ancestor_conversation, class_name: "Conversation"`
- `belongs_to :descendant_conversation, class_name: "Conversation"`

Indexes:

- unique `ancestor_conversation_id, descendant_conversation_id`
- `descendant_conversation_id, depth`
- `ancestor_conversation_id, depth`

Rules:

- every conversation has a self-row with `depth = 0`
- on branch creation, insert one row per ancestor of the parent plus the self-row
- no subtree reparenting in v1

Deletion note:

- conversations should normally be archived, not destroyed
- if destroy is ever used in tests or maintenance code, parent/child tree links should be `restrict` and optional pointer links should be `nullify`

Why this over a gem:

- branch-only append semantics make closure rows cheap to maintain
- subtree and breadcrumb queries become simple and reliable
- no nested-set write amplification
- no gem-specific callbacks controlling the domain model

## Transcript Models

### `ConversationTurn`

Purpose:

- stable transcript exchange slot
- owner of a single workflow
- canonical selector for input and output message variants

Suggested columns:

- `id :bigint`
- `public_id :string, null: false`
- `conversation_id :bigint, null: false`
- `sequence :integer, null: false`
- `trigger_kind :string, null: false`
- `status :string, null: false`
- `queue_position :integer`
- `blocked_by_turn_id :bigint`
- `selected_input_message_id :bigint`
- `selected_output_message_id :bigint`
- `queued_at :datetime`
- `started_at :datetime`
- `finished_at :datetime`
- `latest_activity_at :datetime`
- `metadata :jsonb, null: false, default: {}`
- timestamps

Trigger kinds:

- `user`
- `system`
- `automation`
- `subagent_callback`
- `merge`

Status enum:

- `draft`
- `queued`
- `running`
- `awaiting_approval`
- `finished`
- `errored`
- `stopped`

Associations:

- `belongs_to :conversation`
- `belongs_to :blocked_by_turn, class_name: "ConversationTurn", optional: true`
- `belongs_to :selected_input_message, class_name: "ConversationMessage", optional: true`
- `belongs_to :selected_output_message, class_name: "ConversationMessage", optional: true`
- `has_one :workflow, class_name: "TurnWorkflow", dependent: :destroy`
- `has_many :messages, class_name: "ConversationMessage", dependent: :destroy`

Indexes:

- unique `public_id`
- unique `conversation_id, sequence`
- `conversation_id, latest_activity_at`
- `conversation_id, status`
- `conversation_id, status, queue_position`

Rules:

- `queued` turns represent follow-up inputs submitted while another turn is still active
- queued turns are rendered in the composer/status rail, not the canonical transcript list, until activated
- steering the current turn is implemented by replacing `selected_input_message_id` on the active turn until the first side-effecting workflow node finishes

### `ConversationMessage`

Purpose:

- immutable transcript record
- stores message variants without destructive overwrite

Suggested columns:

- `id :bigint`
- `public_id :string, null: false`
- `conversation_id :bigint, null: false`
- `conversation_turn_id :bigint, null: false`
- `role :string, null: false`
- `slot :string, null: false`
- `variant_kind :string, null: false`
- `replaces_message_id :bigint`
- `content_markdown :text`
- `structured_content :jsonb, null: false, default: {}`
- `metadata :jsonb, null: false, default: {}`
- `tokens_input :integer`
- `tokens_output :integer`
- `usage_payload :jsonb, null: false, default: {}`
- timestamps

Roles:

- `system`
- `developer`
- `user`
- `assistant`
- `character`
- `summary`

Slots:

- `turn_input`
- `turn_output`
- `import_summary`
- `note`

Variant kinds:

- `canonical`
- `rerun`
- `retry`
- `edit`
- `swipe`
- `imported`

Associations:

- `belongs_to :conversation`
- `belongs_to :conversation_turn`
- `belongs_to :replaces_message, class_name: "ConversationMessage", optional: true`
- `has_one :visibility, class_name: "ConversationMessageVisibility", dependent: :destroy`
- `has_many :attachments, class_name: "MessageAttachment", dependent: :destroy`

Indexes:

- unique `public_id`
- `conversation_id, conversation_turn_id, created_at`
- `conversation_turn_id, slot, created_at`
- `replaces_message_id`

### `ConversationMessageVisibility`

Purpose:

- mutable visibility overlay
- keeps transcript records immutable

Suggested columns:

- `conversation_message_id :bigint, null: false`
- `deleted_at :datetime`
- `context_excluded_at :datetime`
- `hidden_at :datetime`
- `hidden_reason :string`
- `metadata :jsonb, null: false, default: {}`
- timestamps

Associations:

- `belongs_to :conversation_message, class_name: "ConversationMessage"`

Indexes:

- unique `conversation_message_id`
- `deleted_at`
- `context_excluded_at`

Rules:

- deleting or excluding a message changes the overlay row, not the message row
- workflow data is not hidden via this mechanism

### `MessageAttachment`

Purpose:

- conversation-local attachment row
- wraps Active Storage with domain metadata and ancestry

Suggested columns:

- `id :bigint`
- `conversation_id :bigint, null: false`
- `conversation_message_id :bigint, null: false`
- `position :integer, null: false`
- `kind :string, null: false`
- `origin_message_attachment_id :bigint`
- `origin_message_id :bigint`
- `origin_conversation_id :bigint`
- `preparation_status :string, null: false`
- `preparation_ref :jsonb, null: false, default: {}`
- `metadata :jsonb, null: false, default: {}`
- timestamps

Kinds:

- `file`
- `image`
- `screenshot`
- `artifact`

Preparation status:

- `pending`
- `prepared`
- `failed`

Associations:

- `belongs_to :conversation`
- `belongs_to :conversation_message, class_name: "ConversationMessage"`
- `belongs_to :origin_message_attachment, class_name: "MessageAttachment", optional: true`
- `belongs_to :origin_message, class_name: "ConversationMessage", optional: true`
- `belongs_to :origin_conversation, class_name: "Conversation", optional: true`

Implementation note:

- the Rails implementation should use `has_one_attached :file` on `MessageAttachment`
- optional origin pointers should use `ON DELETE SET NULL`

Indexes:

- `conversation_message_id, position`
- `conversation_id, preparation_status`
- `origin_message_id`

### `ConversationImport`

Purpose:

- read-only imported prefix or imported summary
- makes branch prefixes and future merge summaries explicit

Suggested columns:

- `id :bigint`
- `target_conversation_id :bigint, null: false`
- `source_conversation_id :bigint, null: false`
- `kind :string, null: false`
- `mode :string, null: false`
- `position :integer, null: false`
- `source_message_id :bigint`
- `source_start_turn_sequence :integer`
- `source_end_turn_sequence :integer`
- `summary_message_id :bigint`
- `active :boolean, null: false, default: true`
- `metadata :jsonb, null: false, default: {}`
- timestamps

Kinds:

- `branch_prefix`
- `merge_summary`
- `quoted_context`

Modes:

- `messages_only`
- `summary_only`
- `messages_plus_summary`

Associations:

- `belongs_to :target_conversation, class_name: "Conversation"`
- `belongs_to :source_conversation, class_name: "Conversation"`
- `belongs_to :source_message, class_name: "ConversationMessage", optional: true`
- `belongs_to :summary_message, class_name: "ConversationMessage", optional: true`

Indexes:

- `target_conversation_id, position`
- `source_conversation_id`
- `active`

### `ConversationSummarySegment`

Purpose:

- compaction without rewriting transcript history
- selected summaries can be imported into context assembly

Suggested columns:

- `id :bigint`
- `conversation_id :bigint, null: false`
- `kind :string, null: false`
- `status :string, null: false`
- `start_turn_sequence :integer, null: false`
- `end_turn_sequence :integer, null: false`
- `summary_message_id :bigint, null: false`
- `replaces_segment_id :bigint`
- `token_estimate :integer`
- `metadata :jsonb, null: false, default: {}`
- timestamps

Kinds:

- `auto_compaction`
- `manual_summary`
- `merge_summary`

Status:

- `active`
- `superseded`

Associations:

- `belongs_to :conversation`
- `belongs_to :summary_message, class_name: "ConversationMessage"`
- `belongs_to :replaces_segment, class_name: "ConversationSummarySegment", optional: true`

Indexes:

- `conversation_id, start_turn_sequence, end_turn_sequence`
- `conversation_id, status`

## Workflow Models

### `TurnWorkflow`

Purpose:

- per-turn DAG aggregate root
- lock boundary for execution mutation

Suggested columns:

- `id :bigint`
- `public_id :string, null: false`
- `conversation_turn_id :bigint, null: false`
- `status :string, null: false`
- `planner_mode :string, null: false`
- `next_ordinal :bigint, null: false, default: 1`
- `ready_nodes_count :integer, null: false, default: 0`
- `running_nodes_count :integer, null: false, default: 0`
- `awaiting_approval_count :integer, null: false, default: 0`
- `active_resource_count :integer, null: false, default: 0`
- `terminal_node_id :bigint`
- `started_at :datetime`
- `finished_at :datetime`
- `last_activity_at :datetime`
- `metadata :jsonb, null: false, default: {}`
- timestamps

Status:

- `draft`
- `running`
- `awaiting_approval`
- `finished`
- `failed`
- `rejected`
- `stopped`

Planner mode:

- `serial_loop`

Associations:

- `belongs_to :conversation_turn`
- `belongs_to :terminal_node, class_name: "WorkflowNode", optional: true`
- `has_many :nodes, class_name: "WorkflowNode", dependent: :destroy`
- `has_many :edges, class_name: "WorkflowEdge", dependent: :destroy`
- `has_many :artifacts, class_name: "WorkflowArtifact", dependent: :destroy`
- `has_many :approval_requests, class_name: "ApprovalRequest", dependent: :destroy`

Indexes:

- unique `public_id`
- unique `conversation_turn_id`
- `status, last_activity_at`

### `WorkflowNode`

Purpose:

- executable or structural node inside a turn workflow

Suggested columns:

- `id :bigint`
- `public_id :string, null: false`
- `turn_workflow_id :bigint, null: false`
- `ordinal :bigint, null: false`
- `node_type :string, null: false`
- `state :string, null: false`
- `key :string`
- `attempt :integer, null: false, default: 1`
- `join_policy :string`
- `reducer_type :string`
- `required_inputs_total :integer, null: false, default: 0`
- `required_inputs_finished :integer, null: false, default: 0`
- `optional_inputs_total :integer, null: false, default: 0`
- `optional_inputs_finished :integer, null: false, default: 0`
- `input_payload :jsonb, null: false, default: {}`
- `output_payload :jsonb, null: false, default: {}`
- `error_payload :jsonb, null: false, default: {}`
- `claimed_at :datetime`
- `claimed_by :string`
- `lease_expires_at :datetime`
- `heartbeat_at :datetime`
- `started_at :datetime`
- `finished_at :datetime`
- `metadata :jsonb, null: false, default: {}`
- timestamps

Node types:

- `model_step`
- `tool_call`
- `command_exec`
- `subagent_run`
- `join`
- `approval_gate`
- `finalize`
- `summary`

State:

- `ready`
- `blocked`
- `running`
- `awaiting_approval`
- `finished`
- `failed`
- `rejected`
- `skipped`
- `canceled`
- `timed_out`

Associations:

- `belongs_to :turn_workflow`
- `has_many :incoming_edges, class_name: "WorkflowEdge", foreign_key: :to_node_id, dependent: :destroy`
- `has_many :outgoing_edges, class_name: "WorkflowEdge", foreign_key: :from_node_id, dependent: :destroy`
- `has_many :events, class_name: "WorkflowNodeEvent", dependent: :destroy`
- `has_many :artifacts, class_name: "WorkflowArtifact", dependent: :destroy`
- `has_many :subagent_runs, dependent: :destroy`
- `has_many :process_runs, dependent: :destroy`
- `has_many :approval_requests, dependent: :destroy`

Indexes:

- unique `public_id`
- unique `turn_workflow_id, ordinal`
- unique `turn_workflow_id, key` where key is present
- `turn_workflow_id, state, lease_expires_at`
- `turn_workflow_id, node_type, state`

Important invariant:

- edges may only point from a lower `ordinal` to a higher `ordinal`

This makes cycles impossible without requiring recursive cycle checks on every edge creation.

### `WorkflowEdge`

Purpose:

- dependency edge inside a turn workflow

Suggested columns:

- `id :bigint`
- `turn_workflow_id :bigint, null: false`
- `from_node_id :bigint, null: false`
- `to_node_id :bigint, null: false`
- `required :boolean, null: false, default: true`
- `group_key :string`
- `metadata :jsonb, null: false, default: {}`
- timestamps

Associations:

- `belongs_to :turn_workflow`
- `belongs_to :from_node, class_name: "WorkflowNode"`
- `belongs_to :to_node, class_name: "WorkflowNode"`

Indexes:

- unique `from_node_id, to_node_id`
- `turn_workflow_id, to_node_id, required`
- `turn_workflow_id, from_node_id`

Rules:

- no edge type enum is needed in v1
- all edges are dependency edges
- optional fan-in is expressed by `required = false`

### `WorkflowNodeEvent`

Purpose:

- bounded append-only event stream for progress, activity, and diagnostics

Suggested columns:

- `id :bigint`
- `turn_workflow_id :bigint, null: false`
- `workflow_node_id :bigint, null: false`
- `kind :string, null: false`
- `payload :jsonb, null: false, default: {}`
- `text :text`
- timestamps

Kinds:

- `status_changed`
- `activity`
- `output_delta`
- `approval_requested`
- `approval_resolved`
- `diagnostic`
- `resource_linked`

Indexes:

- `workflow_node_id, id`
- `turn_workflow_id, id`
- `turn_workflow_id, workflow_node_id, kind, id`

Retention:

- keep append-only semantics
- allow compaction for noisy `output_delta` streams
- never use these rows as transcript truth

### `WorkflowArtifact`

Purpose:

- durable structured outputs from workflow nodes

Suggested columns:

- `id :bigint`
- `turn_workflow_id :bigint, null: false`
- `workflow_node_id :bigint, null: false`
- `kind :string, null: false`
- `storage_mode :string, null: false`
- `payload :jsonb, null: false, default: {}`
- `metadata :jsonb, null: false, default: {}`
- timestamps

Kinds:

- `tool_result`
- `file_ref`
- `image_ref`
- `patch`
- `structured_result`
- `join_result`
- `assistant_output_candidate`
- `log_ref`

Storage modes:

- `inline_json`
- `active_storage`
- `foreign_reference`
- `external_url`

Indexes:

- `workflow_node_id, kind`
- `turn_workflow_id, kind`

Implementation note:

- the Rails implementation should use `has_one_attached :file` when `storage_mode == "active_storage"`
- optional artifact-pointer foreign keys should use `ON DELETE SET NULL`

## Resource Models

### `SubagentRun`

Purpose:

- durable control-plane row for a child agent execution owned by a workflow node

Suggested columns:

- `id :bigint`
- `public_id :string, null: false`
- `workflow_node_id :bigint, null: false`
- `turn_workflow_id :bigint, null: false`
- `conversation_turn_id :bigint, null: false`
- `conversation_id :bigint, null: false`
- `child_conversation_id :bigint`
- `external_session_ref :string`
- `status :string, null: false`
- `management_mode :string, null: false`
- `latest_snapshot :jsonb, null: false, default: {}`
- `result_artifact_id :bigint`
- `claimed_at :datetime`
- `lease_expires_at :datetime`
- `heartbeat_at :datetime`
- `started_at :datetime`
- `finished_at :datetime`
- `close_reason :string`
- `metadata :jsonb, null: false, default: {}`
- timestamps

Status:

- `starting`
- `running`
- `waiting`
- `succeeded`
- `failed`
- `killed`
- `timed_out`
- `lost`
- `closed`

Management mode:

- `managed`
- `read_only_external`

Associations:

- `belongs_to :workflow_node`
- `belongs_to :turn_workflow`
- `belongs_to :conversation_turn`
- `belongs_to :conversation`
- `belongs_to :child_conversation, class_name: "Conversation", optional: true`
- `belongs_to :result_artifact, class_name: "WorkflowArtifact", optional: true`

Indexes:

- unique `public_id`
- `workflow_node_id, started_at`
- `child_conversation_id`
- `status, lease_expires_at`

### `ProcessRun`

Purpose:

- durable control-plane row for shell commands and background services

Suggested columns:

- `id :bigint`
- `public_id :string, null: false`
- `workflow_node_id :bigint, null: false`
- `turn_workflow_id :bigint, null: false`
- `conversation_turn_id :bigint, null: false`
- `conversation_id :bigint, null: false`
- `kind :string, null: false`
- `status :string, null: false`
- `started_by_type :string, null: false`
- `title :string`
- `command :text, null: false`
- `cwd :text`
- `env_preview :jsonb, null: false, default: {}`
- `port_hints :jsonb, null: false, default: []`
- `log_path :text`
- `pid :integer`
- `pgid :integer`
- `log_artifact_id :bigint`
- `timeout_s :integer`
- `exit_code :integer`
- `terminal_reason :string`
- `claimed_at :datetime`
- `lease_expires_at :datetime`
- `heartbeat_at :datetime`
- `started_at :datetime`
- `finished_at :datetime`
- `metadata :jsonb, null: false, default: {}`
- timestamps

Kind:

- `turn_command`
- `background_service`

Status:

- `starting`
- `running`
- `succeeded`
- `failed`
- `killed`
- `timed_out`
- `lost`
- `closed`

Associations:

- `belongs_to :workflow_node`
- `belongs_to :turn_workflow`
- `belongs_to :conversation_turn`
- `belongs_to :conversation`
- `belongs_to :log_artifact, class_name: "WorkflowArtifact", optional: true`

Indexes:

- unique `public_id`
- `workflow_node_id, started_at`
- `conversation_turn_id, status`
- `conversation_id, kind, status`
- `status, lease_expires_at`

Rules:

- `turn_command` must never outlive its owner turn
- `background_service` may outlive the owner turn if explicitly marked durable

### `ApprovalRequest`

Purpose:

- stable audit record for approval-gated workflow operations

Suggested columns:

- `id :bigint`
- `workflow_node_id :bigint, null: false`
- `turn_workflow_id :bigint, null: false`
- `scope :string, null: false`
- `status :string, null: false`
- `preview_payload :jsonb, null: false, default: {}`
- `decision_payload :jsonb, null: false, default: {}`
- `resolved_by_actor_type :string`
- `resolved_by_actor_id :bigint`
- `resolved_at :datetime`
- timestamps

Scope:

- `tool_call`
- `command_exec`
- `subagent`
- `message_edit`
- `external_write`

Status:

- `pending`
- `approved`
- `denied`
- `expired`
- `canceled`

Indexes:

- `workflow_node_id, status`
- `turn_workflow_id, status`

### `ExecutionLease`

Purpose:

- explicit capacity and ownership lease row for active execution
- keeps distributed lease bookkeeping out of workflow/resource metadata blobs

Suggested columns:

- `id :bigint`
- `subject_type :string, null: false`
- `subject_id :bigint, null: false`
- `holder_type :string, null: false`
- `holder_id :bigint, null: false`
- `execution_request_key :string, null: false`
- `slots :integer, null: false, default: 1`
- `status :string, null: false`
- `lease_expires_at :datetime, null: false`
- `heartbeat_at :datetime, null: false`
- `recovery_metadata :jsonb, null: false, default: {}`
- timestamps

Status:

- `active`
- `released`
- `expired`

Indexes:

- unique `subject_type, subject_id, execution_request_key`
- `holder_type, holder_id, status`
- `status, lease_expires_at`

## Supporting Models

These models are not part of the tree/workflow core, but they are part of the product surface and should exist in a greenfield design from day one.

### `ConversationDraft`

Purpose:

- durable unsent composer state
- branch prefill
- reusable attachment refs before submit

Suggested columns:

- `id :bigint`
- `conversation_id :bigint, null: false`
- `content_markdown :text`
- `selected_agent_id :bigint`
- `permission_mode :string`
- `attachment_refs :jsonb, null: false, default: []`
- `metadata :jsonb, null: false, default: {}`
- `updated_by_actor_type :string`
- `updated_by_actor_id :bigint`
- timestamps

Associations:

- `belongs_to :conversation`
- `belongs_to :selected_agent, class_name: "Agent", optional: true`

Indexes:

- unique `conversation_id`

Notes:

- `attachment_refs` are draft-only references
- submit materializes them into `MessageAttachment` rows on the new input message

### `ToolPermissionGrant`

Purpose:

- durable approval memory for exec/tool policies
- supports Codex-like prefix rules and approved capability scopes

Suggested columns:

- `id :bigint`
- `subject_type :string, null: false`
- `subject_id :bigint, null: false`
- `tool_name :string, null: false`
- `scope_kind :string, null: false`
- `pattern :string`
- `status :string, null: false`
- `granted_by_actor_type :string`
- `granted_by_actor_id :bigint`
- `expires_at :datetime`
- `metadata :jsonb, null: false, default: {}`
- timestamps

Scope kinds:

- `exact_call`
- `prefix_rule`
- `tool_family`
- `conversation_local`
- `workspace_local`

Status:

- `active`
- `revoked`
- `expired`

Indexes:

- `subject_type, subject_id, tool_name, status`
- `expires_at`

Notes:

- this model is separate from `ApprovalRequest`
- `ApprovalRequest` records one approval decision for one workflow node
- `ToolPermissionGrant` records durable future permission

### `WorkspaceDocument`

Purpose:

- durable workspace memory / notes / documents searched by tools
- keeps memory out of transcript and out of workflow graph structure

Suggested columns:

- `id :bigint`
- `conversation_id :bigint`
- `conversation_scope :string, null: false`
- `path :string, null: false`
- `title :string`
- `status :string, null: false`
- `latest_revision_id :bigint`
- `metadata :jsonb, null: false, default: {}`
- timestamps

Conversation scope:

- `conversation_local`
- `tree_shared`
- `agent_local`
- `global`

Status:

- `active`
- `archived`

Indexes:

- `conversation_id, conversation_scope`
- unique `conversation_id, path, conversation_scope`

### `WorkspaceDocumentRevision`

Purpose:

- append-only durable revisions for workspace memory documents

Suggested columns:

- `id :bigint`
- `workspace_document_id :bigint, null: false`
- `body_markdown :text, null: false`
- `source_kind :string, null: false`
- `workflow_artifact_id :bigint`
- `metadata :jsonb, null: false, default: {}`
- timestamps

Source kinds:

- `manual`
- `memory_tool`
- `subagent_result`
- `system`

Indexes:

- `workspace_document_id, created_at`

### `Agent`

Purpose:

- stable runtime configuration and profile boundary for a conversation

Suggested columns:

- `id :bigint`
- `public_id :string, null: false`
- `name :string, null: false`
- `status :string, null: false`
- `runtime_kind :string, null: false`
- `default_timeout_s :integer`
- `tool_policy_mode :string, null: false`
- `config :jsonb, null: false, default: {}`
- timestamps

Notes:

- keep agent/runtime configuration out of conversation metadata
- `ConversationDraft.selected_agent_id` and conversation defaults should point here

### `ToolCallFact`

Purpose:

- append-only analytics projection for tool reliability and execution-scope reporting
- derived from workflow nodes, approval rows, and terminal resource state

Suggested columns:

- `id :bigint`
- `conversation_id :bigint, null: false`
- `conversation_turn_id :bigint, null: false`
- `turn_workflow_id :bigint, null: false`
- `workflow_node_id :bigint, null: false`
- `tool_name :string, null: false`
- `tool_family :string`
- `execution_scope :string, null: false`
- `result_status :string, null: false`
- `failure_class :string`
- `approval_status :string`
- `model_attempts :integer, null: false, default: 0`
- `tool_executions :integer, null: false, default: 0`
- `latency_ms :integer`
- `metadata :jsonb, null: false, default: {}`
- timestamps

Execution scope:

- `parent`
- `subagent`

Indexes:

- `tool_name, created_at`
- `execution_scope, result_status, created_at`
- `conversation_id, created_at`

Notes:

- this is a projection table, not workflow truth
- rebuild/backfill should remain possible from workflow facts

## Workflow Semantics

### Planner Model

Each turn uses a serial planner loop at the decision level.

- one `model_step` decides what to do next
- the `model_step` may create multiple child nodes:
  - multiple `tool_call`
  - multiple `command_exec`
  - multiple `subagent_run`
- a `join` node collects those child results
- a later `model_step` or `finalize` consumes the join result

Macro conversation remains serial. Micro execution inside a turn can be parallel.

## Operational Invariants

These invariants should be protected by validations, indexes, and service-layer checks.

- every conversation has exactly one self-row in `ConversationClosure`
- child conversations always inherit `root_conversation_id` from the root ancestor
- `ConversationTurn.sequence` is unique per conversation and assigned at enqueue time
- queued turns are hidden from the canonical transcript query until activated
- every turn has at most one selected input and one selected output pointer
- `WorkflowEdge` always points from lower ordinal to higher ordinal
- a `finalize` node is the only node allowed to materialize canonical assistant output
- a `turn_command` resource must always have `workflow_node_id`, `conversation_turn_id`, and `conversation_id`
- an active execution lease is always recoverable by `execution_request_key`

### Join Model

`join` is a reducer node, not just a waiter.

Join configuration lives on the `WorkflowNode` row:

- `join_policy`
  - `all_required`
  - `best_effort`
  - `first_success`
- `reducer_type`
  - `collect_tool_results`
  - `collect_subagent_results`
  - `compose_research_bundle`
  - `compose_patch_candidates`

Join output is emitted as a `WorkflowArtifact(kind: "join_result")`.

Downstream nodes should consume that join artifact rather than scan all child nodes.

### Finalize

Every turn ends with exactly one `finalize` node.

Rules:

- only `finalize` can produce the selected assistant output message
- tool calls and subagents never write directly to transcript
- `finalize` can:
  - select an `assistant_output_candidate`
  - compose a fresh assistant message
  - emit a summary message
  - fail the turn cleanly if required results are unavailable

## State And Safety Rules

### Transcript Rules

- transcript messages are append-only
- mutable visibility lives in overlay rows
- selected pointers on `ConversationTurn` choose the canonical input and output

### Workflow Rules

- workflow mutation is locked at the `TurnWorkflow` row only
- ready-node claiming uses `FOR UPDATE SKIP LOCKED`
- lease and heartbeat live on nodes and resources
- no graph-wide lock across the whole conversation

### Resource Rules

- stopping a turn must stop all active required resources owned by its workflow
- finishing a turn must close all non-durable turn-owned resources
- required active resources block `finalize`

### Failure Propagation

Failure propagation is local to the workflow.

- a child failure does not automatically fail the transcript turn
- join policy decides whether failure blocks completion
- optional failed children remain part of join output as structured failure summaries
- approval-denied nodes should transition to `rejected`
- dependency branches that are no longer needed should transition to `skipped`

### Approval Rules

- approval blocks workflow execution, not transcript history
- approval decision is stored in `ApprovalRequest`
- `approval_gate` nodes transition through `awaiting_approval`

### Visibility Rules

- only transcript messages support delete/exclude/hide overlays
- workflow truth is not hidden; it is projected in a bounded way
- raw process logs and child transcripts are not directly injected into model context

## Branching, Editing, Retry, Rerun, Swipe

### Branching From Historical Messages

Create a child conversation.

- create `Conversation`
- create closure rows
- create `ConversationImport(kind: "branch_prefix")`
- prefill a new draft turn in the child conversation
- clone attachment refs into draft state only

No transcript history is copied.

### Message Editing

Editing an input message creates a new message variant.

- append a new `ConversationMessage(slot: "turn_input", variant_kind: "edit")`
- update `ConversationTurn.selected_input_message_id`
- create a new workflow run or rerun workflow for the turn
- downstream turn invalidation policy is an application-level rule

### Retry / Rerun

Retry and rerun are pointer-based and append-only.

- append new workflow nodes and new output message variants
- update `ConversationTurn.selected_output_message_id` only when the user adopts the result or policy allows automatic replacement

### Swipe

Swipe becomes cheap.

- all assistant output variants remain immutable `ConversationMessage` rows
- `ConversationTurn.selected_output_message_id` is the active pointer
- no archive/unarchive of graph nodes is needed

This is deliberately Git-like pointer movement instead of history mutation.

## Context Assembly

The context assembler should not walk a global graph.

It builds context from four sources only:

- base rules
  - account / agent / conversation system and developer instructions
- active imports
  - branch prefix
  - merge summary
  - quoted context
- local transcript tail
  - selected input/output messages from recent turns
- current workflow outputs
  - selected join artifacts
  - selected summary artifacts

Excluded by default:

- raw command logs
- child conversation full transcript
- verbose workflow event streams

These can be summarized or attached as bounded artifacts instead.

## Tree Navigation And UI Query Strategy

The tree-navigation query requirements remain valid, but the concrete UI/query-contract work is intentionally deferred from the current backend-only slice.

When the backend foundation is complete, move to [CoreMatrix Agent UI And Runtime Follow-Up](./2026-03-23-core-matrix-agent-ui-runtime-follow-up.md) for:

- controller/query contract design
- tree navigation delivery shape
- transcript rendering payloads
- realtime event delivery choices

## Suggested Rails Application Services

### Conversation Tree / Transcript

- `Conversations::CreateRoot`
- `Conversations::CreateBranch`
- `Conversations::AddImport`
- `Conversations::TreeQuery`
- `Conversations::BreadcrumbQuery`
- `Turns::StartUserTurn`
- `Turns::QueueFollowUp`
- `Turns::SteerCurrentInput`
- `Turns::FinalizeOutput`
- `Turns::AdoptOutputVariant`
- `Messages::EditInputVariant`
- `Messages::UpdateVisibility`
- `Attachments::MaterializeRefs`

### Workflow

- `Workflows::Mutator`
- `Workflows::Scheduler`
- `Workflows::NodeClaimer`
- `Workflows::NodeRunner`
- `Workflows::JoinReducer`
- `Workflows::FailurePropagator`
- `Workflows::LeaseReclaimer`
- `Workflows::ContextAssembler`

### Resources

- `Processes::Start`
- `Processes::Stop`
- `Processes::Reconcile`
- `Subagents::Spawn`
- `Subagents::Poll`
- `Subagents::Wait`
- `Subagents::Interrupt`
- `Subagents::Close`
- `Approvals::Request`
- `Approvals::Resolve`
- `Leases::Acquire`
- `Leases::Heartbeat`
- `Leases::Release`

### Supporting Contexts

- `Drafts::UpdateConversationDraft`
- `Permissions::GrantFromApproval`
- `Permissions::ResolveEffectiveToolPolicy`
- `Statistics::ProjectToolCallFacts`
- `WorkspaceMemory::SearchDocuments`
- `WorkspaceMemory::AppendRevision`

## Why This Is Cleaner Than A Global Conversation DAG

- transcript and execution are different abstractions
- tree navigation is optimized as a tree, not derived from a graph
- concurrency is local to a turn where it actually matters
- joins are explicit and reducible
- swipe / rerun / retry are pointer updates over immutable variants
- no graph-wide active/inactive semantics over the entire conversation history
- no graph-wide closure traversal for everyday transcript rendering
- no cycle-check cost on every edge, because workflow edges obey ordinal monotonicity

## Capability Coverage Against Current Cybros

This design is intended to cover the current product/runtime surface while simplifying the core model.

| Current capability | Greenfield design |
|---|---|
| Root / branch conversation hierarchy | `Conversation` + `ConversationClosure` |
| Historical message branch | `ConversationImport(kind: "branch_prefix")` + child conversation |
| Reusable attachment refs | `MessageAttachment.origin_*` + draft ref materialization |
| Composer draft persistence | `ConversationDraft` |
| Ordered transcript page | `ConversationTurn.sequence` + selected message pointers |
| Queued follow-up input while a turn is active | `ConversationTurn(status: "queued")` + `queue_position` |
| Steer current turn before side effects | active-turn input variants + `selected_input_message_id` swap |
| System / developer / user / assistant / character messages | `ConversationMessage.role` |
| Summary / compaction | `ConversationSummarySegment` + importable summary messages |
| Pending / running / finished turn state | `ConversationTurn.status` |
| Tool loop | `TurnWorkflow` + `WorkflowNode(node_type: "tool_call")` |
| Concurrent tool execution | multiple ready child nodes within one workflow |
| Subagent spawn / poll / wait / close / interrupt | `SubagentRun` + resource services |
| Parent-owned subagent join | `join` + `finalize`, never child transcript direct write |
| Turn-scoped exec streaming | `ProcessRun(kind: "turn_command")` + `WorkflowNodeEvent` + log artifact |
| Background process control plane | `ProcessRun(kind: "background_service")` |
| Approval gate | `ApprovalRequest` + `approval_gate` node |
| Durable approval rules / prefix rules | `ToolPermissionGrant` |
| Lease and heartbeat | `ExecutionLease` + heartbeat fields on `WorkflowNode`, `SubagentRun`, `ProcessRun` |
| Failure propagation | workflow-local join and reducer rules |
| Retry / rerun | append-only node and message variants |
| Swipe / adopt version | `ConversationTurn.selected_output_message_id` |
| Edit input and rerun | new input message variant + rerun workflow |
| Soft delete / context exclude | `ConversationMessageVisibility` |
| Workspace memory / durable notes | `WorkspaceDocument` + `WorkspaceDocumentRevision` |
| Context assembly with inherited prefix | imports + local transcript tail + workflow artifacts |
| Activity rollup / bounded diagnostics | `WorkflowNodeEvent` + workflow projections |
| Tool reliability statistics | `ToolCallFact` projection |
| Managed child conversation read-only | `Conversation.managed_by_subagent_run_id` + application policy |

## Migration Strategy For A New Project

Because this is a greenfield design:

- start with the models and indexes above
- do not carry forward current Cybros DAG tables
- do not add compatibility layers for lane-based graph semantics
- keep each layer narrow from day one

The only recommended projections to materialize early are:

- conversation tree closure rows
- latest activity columns on conversation and turn
- selected input/output pointers on turns
- workflow ready/running/approval counts

## Deferred Questions

These are intentionally deferred because they do not block the first clean implementation.

- whether `public_id` should later move from UUID to UUIDv7 or ULID
- whether process logs should remain disk-backed only or be mirrored into Active Storage after completion
- whether summary segments should become user-selectable instead of automatically managed

## Recommendation

Build the new project with:

- `Conversation` tree for navigation
- append-only transcript turns and messages
- per-turn workflow DAG for concurrency and orchestration
- explicit resources for subagents and processes
- imports and summaries instead of global graph merge

This is the cleanest way to preserve Cybros' strongest capabilities while removing the biggest structural costs of a global conversation DAG.
