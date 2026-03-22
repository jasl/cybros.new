# Greenfield Agent Rails Bootstrap Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Bootstrap the backend foundation for the greenfield conversation-tree plus per-turn-workflow design inside the existing `core_matrix` Rails app, with concrete generator commands, model skeletons, and a safe creation order.

**Architecture:** Keep user-visible history as a `Conversation` tree with append-only transcript rows, and put concurrency only inside `TurnWorkflow`. Model subagents, commands, approvals, leases, and analytics as explicit control-plane records instead of hiding them in one global DAG or in oversized JSON blobs. This document stops at backend/domain implementation and deliberately defers controllers, Action Cable, UI, and runtime adapters to [CoreMatrix Agent UI And Runtime Follow-Up](./2026-03-23-core-matrix-agent-ui-runtime-follow-up.md).

**Tech Stack:** Rails 8.2 defaults, PostgreSQL, Active Storage, Minitest.

---

## Verification Notes

I verified the CLI shape before writing this:

- local Rails 8 help confirms:
  - `bin/rails generate model NAME field:type`
  - `references` works for normal associations
  - `bin/rails active_storage:install`
- local `--pretend` runs confirm `jsonb` works in `generate model`

The current `core_matrix` app already provides:

- PostgreSQL and multi-database wiring
- Active Storage framework loading
- Solid Queue / Cache / Cable infrastructure

The current slice should not modify controllers, views, channels, or JavaScript UI code.

Important generator rule:

- use `:references` only when the generated foreign key target name matches the real table name
- for self-references or aliased foreign keys such as `parent_conversation_id`, `from_node_id`, `owner_node_id`, use raw `:bigint` columns and wire the foreign keys manually in the migration

This is the safest Rails-first path.

## V1 Implementation Defaults

These are fixed defaults for the first build. They reduce ambiguity and lower implementation risk.

- use string-backed Rails enums, not PostgreSQL enum types
- use plain UUID strings for `public_id`
- use closure-table rows for conversation tree queries
- use `has_one_attached` for `MessageAttachment` and `WorkflowArtifact`
- allow only one active workflow per conversation at a time
- allow only one open approval request per workflow node at a time
- ship only `all_required` and `best_effort` join policies in v1
- forbid nested subagent spawn in v1
- ship background services in v1, but only with start/list/stop/reconcile
- do not ship a user-facing transcript merge UI in v1
- prefer archive/close over hard destroy for conversation records

## CoreMatrix Baseline Preparation

Run from the existing project directory:

```bash
cd core_matrix
bin/rails active_storage:install # only if the migration is not already present
mkdir -p \
  app/models/concerns \
  app/services/conversations \
  app/services/turns \
  app/services/workflows \
  app/services/subagents \
  app/services/processes \
  app/services/approvals \
  app/services/leases \
  app/services/attachments \
  app/services/drafts \
  app/services/permissions \
  app/services/statistics \
  app/queries/conversations \
  app/queries/transcript \
  app/queries/workflows \
  test/services \
  test/queries \
  test/support
```

Expected baseline before starting the domain implementation:

- `core_matrix` remains the target app; do not create another Rails app
- Active Storage is installed at the database level
- backend directories for concerns, services, queries, and backend test support exist
- `bun run lint:js` no longer fails just because `test/js` is absent
- existing Solid Queue / Cache / Cable setup remains in place but is not expanded in this slice
- the implementation stops before controller, channel, view, or JavaScript work

## Target Directory Structure

```text
app/
  models/
    concerns/
      has_public_id.rb
    agent.rb
    conversation.rb
    conversation_closure.rb
    conversation_turn.rb
    conversation_message.rb
    conversation_message_visibility.rb
    message_attachment.rb
    conversation_import.rb
    conversation_summary_segment.rb
    turn_workflow.rb
    workflow_node.rb
    workflow_edge.rb
    workflow_node_event.rb
    workflow_artifact.rb
    subagent_run.rb
    process_run.rb
    approval_request.rb
    execution_lease.rb
    conversation_draft.rb
    tool_permission_grant.rb
    workspace_document.rb
    workspace_document_revision.rb
    tool_call_fact.rb
  services/
    conversations/
      create_root.rb
      create_branch.rb
      add_import.rb
    turns/
      start_user_turn.rb
      queue_follow_up.rb
      steer_current_input.rb
      finalize_output.rb
      adopt_output_variant.rb
    workflows/
      mutator.rb
      scheduler.rb
      node_claimer.rb
      node_runner.rb
      join_reducer.rb
      failure_propagator.rb
      context_assembler.rb
    subagents/
      spawn.rb
      poll.rb
      wait.rb
      interrupt.rb
      close.rb
    processes/
      start.rb
      stop.rb
      reconcile.rb
    approvals/
      request.rb
      resolve.rb
    leases/
      acquire.rb
      heartbeat.rb
      release.rb
    attachments/
      materialize_refs.rb
    drafts/
      update_conversation_draft.rb
    permissions/
      grant_from_approval.rb
      resolve_effective_tool_policy.rb
    statistics/
      project_tool_call_facts.rb
  queries/
    conversations/
      tree_query.rb
      breadcrumb_query.rb
      subtree_query.rb
    transcript/
      visible_messages_query.rb
    workflows/
      ready_nodes_query.rb
      event_feed_query.rb
db/
  migrate/
test/
  models/
  services/
  queries/
  support/
```

## Generation Order

The order below avoids circular pain and keeps the early migrations readable.

### Phase 0: Baseline

- verify `core_matrix` is the target project
- verify Active Storage migration exists and has been applied
- verify the backend skeleton directories exist
- verify baseline verification commands are green enough to start backend work
- do not touch controllers, channels, views, or JavaScript in this phase

### Phase 1: Foundation

```bash
bin/rails generate model Agent \
  public_id:string \
  name:string \
  status:string \
  runtime_kind:string \
  tool_policy_mode:string \
  default_timeout_s:integer \
  config:jsonb

bin/rails generate model Conversation \
  public_id:string \
  agent:references \
  title:string \
  status:string \
  parent_conversation_id:bigint \
  root_conversation_id:bigint \
  branched_from_message_id:bigint \
  branched_from_turn_id:bigint \
  depth:integer \
  branch_position:integer \
  children_count:integer \
  latest_turn_id:bigint \
  latest_message_id:bigint \
  latest_activity_at:datetime \
  managed_by_subagent_run_id:bigint \
  metadata:jsonb

bin/rails generate model ConversationClosure \
  ancestor_conversation_id:bigint \
  descendant_conversation_id:bigint \
  depth:integer
```

### Phase 2: Transcript

```bash
bin/rails generate model ConversationTurn \
  public_id:string \
  conversation:references \
  sequence:integer \
  trigger_kind:string \
  status:string \
  queue_position:integer \
  blocked_by_turn_id:bigint \
  selected_input_message_id:bigint \
  selected_output_message_id:bigint \
  queued_at:datetime \
  started_at:datetime \
  finished_at:datetime \
  latest_activity_at:datetime \
  metadata:jsonb

bin/rails generate model ConversationMessage \
  public_id:string \
  conversation:references \
  conversation_turn:references \
  role:string \
  slot:string \
  variant_kind:string \
  replaces_message_id:bigint \
  content_markdown:text \
  structured_content:jsonb \
  metadata:jsonb \
  tokens_input:integer \
  tokens_output:integer \
  usage_payload:jsonb

bin/rails generate model ConversationMessageVisibility \
  conversation_message:references \
  deleted_at:datetime \
  context_excluded_at:datetime \
  hidden_at:datetime \
  hidden_reason:string \
  metadata:jsonb

bin/rails generate model MessageAttachment \
  conversation:references \
  conversation_message:references \
  position:integer \
  kind:string \
  origin_message_attachment_id:bigint \
  origin_message_id:bigint \
  origin_conversation_id:bigint \
  preparation_status:string \
  preparation_ref:jsonb \
  sha256_digest:string \
  metadata:jsonb

bin/rails generate model ConversationImport \
  target_conversation_id:bigint \
  source_conversation_id:bigint \
  kind:string \
  mode:string \
  position:integer \
  source_message_id:bigint \
  source_start_turn_sequence:integer \
  source_end_turn_sequence:integer \
  summary_message_id:bigint \
  active:boolean \
  metadata:jsonb

bin/rails generate model ConversationSummarySegment \
  conversation:references \
  kind:string \
  status:string \
  start_turn_sequence:integer \
  end_turn_sequence:integer \
  summary_message_id:bigint \
  replaces_segment_id:bigint \
  token_estimate:integer \
  metadata:jsonb
```

### Phase 3: Workflow

```bash
bin/rails generate model TurnWorkflow \
  public_id:string \
  conversation_turn:references \
  status:string \
  planner_mode:string \
  next_ordinal:bigint \
  ready_nodes_count:integer \
  running_nodes_count:integer \
  awaiting_approval_count:integer \
  active_resource_count:integer \
  terminal_node_id:bigint \
  started_at:datetime \
  finished_at:datetime \
  last_activity_at:datetime \
  metadata:jsonb

bin/rails generate model WorkflowNode \
  public_id:string \
  turn_workflow:references \
  ordinal:bigint \
  node_type:string \
  state:string \
  key:string \
  attempt:integer \
  join_policy:string \
  reducer_type:string \
  required_inputs_total:integer \
  required_inputs_finished:integer \
  optional_inputs_total:integer \
  optional_inputs_finished:integer \
  input_payload:jsonb \
  output_payload:jsonb \
  error_payload:jsonb \
  claimed_at:datetime \
  claimed_by:string \
  lease_expires_at:datetime \
  heartbeat_at:datetime \
  started_at:datetime \
  finished_at:datetime \
  metadata:jsonb

bin/rails generate model WorkflowEdge \
  turn_workflow:references \
  from_node_id:bigint \
  to_node_id:bigint \
  required:boolean \
  group_key:string \
  metadata:jsonb

bin/rails generate model WorkflowNodeEvent \
  turn_workflow:references \
  workflow_node:references \
  kind:string \
  payload:jsonb \
  text:text

bin/rails generate model WorkflowArtifact \
  turn_workflow:references \
  workflow_node:references \
  kind:string \
  storage_mode:string \
  payload:jsonb \
  metadata:jsonb
```

### Phase 4: Execution Resources And Control Plane

```bash
bin/rails generate model SubagentRun \
  public_id:string \
  workflow_node:references \
  turn_workflow:references \
  conversation_turn:references \
  conversation:references \
  child_conversation_id:bigint \
  external_session_ref:string \
  status:string \
  management_mode:string \
  latest_snapshot:jsonb \
  result_artifact_id:bigint \
  claimed_at:datetime \
  lease_expires_at:datetime \
  heartbeat_at:datetime \
  started_at:datetime \
  finished_at:datetime \
  close_reason:string \
  metadata:jsonb

bin/rails generate model ProcessRun \
  public_id:string \
  workflow_node:references \
  turn_workflow:references \
  conversation_turn:references \
  conversation:references \
  kind:string \
  status:string \
  started_by_type:string \
  title:string \
  command:text \
  cwd:text \
  env_preview:jsonb \
  port_hints:jsonb \
  log_path:text \
  pid:integer \
  pgid:integer \
  log_artifact_id:bigint \
  timeout_s:integer \
  exit_code:integer \
  terminal_reason:string \
  claimed_at:datetime \
  lease_expires_at:datetime \
  heartbeat_at:datetime \
  started_at:datetime \
  finished_at:datetime \
  metadata:jsonb

bin/rails generate model ApprovalRequest \
  workflow_node:references \
  turn_workflow:references \
  scope:string \
  status:string \
  preview_payload:jsonb \
  decision_payload:jsonb \
  resolved_by_actor_type:string \
  resolved_by_actor_id:bigint \
  resolved_at:datetime

bin/rails generate model ExecutionLease \
  subject_type:string \
  subject_id:bigint \
  holder_type:string \
  holder_id:bigint \
  execution_request_key:string \
  slots:integer \
  status:string \
  lease_expires_at:datetime \
  heartbeat_at:datetime \
  recovery_metadata:jsonb
```

### Phase 5: Product Support And Projections

```bash
bin/rails generate model ConversationDraft \
  conversation:references \
  content_markdown:text \
  selected_agent:references \
  permission_mode:string \
  attachment_refs:jsonb \
  metadata:jsonb \
  updated_by_actor_type:string \
  updated_by_actor_id:bigint

bin/rails generate model ToolPermissionGrant \
  subject_type:string \
  subject_id:bigint \
  tool_name:string \
  scope_kind:string \
  pattern:string \
  status:string \
  granted_by_actor_type:string \
  granted_by_actor_id:bigint \
  expires_at:datetime \
  metadata:jsonb

bin/rails generate model WorkspaceDocument \
  conversation:references \
  conversation_scope:string \
  path:string \
  title:string \
  status:string \
  latest_revision_id:bigint \
  metadata:jsonb

bin/rails generate model WorkspaceDocumentRevision \
  workspace_document:references \
  body_markdown:text \
  source_kind:string \
  workflow_artifact_id:bigint \
  metadata:jsonb

bin/rails generate model ToolCallFact \
  conversation:references \
  conversation_turn:references \
  turn_workflow:references \
  workflow_node:references \
  tool_name:string \
  tool_family:string \
  execution_scope:string \
  result_status:string \
  failure_class:string \
  approval_status:string \
  model_attempts:integer \
  tool_executions:integer \
  latency_ms:integer \
  metadata:jsonb
```

## Migration Sequencing

Use this sequence exactly:

1. run all generator commands above
2. edit every generated migration in place
3. add manual foreign keys and composite indexes
4. only then run `bin/rails db:prepare`
5. paste the model skeletons
6. create empty service/query classes
7. start writing tests against the service layer

Do not run a half-finished schema and “fix it later”. Since this is greenfield, the fastest path is to get the first migration batch right once.

## Mandatory Migration Hardening Before `db:migrate`

Do not blindly run `db:migrate` right after the generators. Edit the generated migrations first.

### Global Rules

- make all status / kind / role / mode columns `null: false`
- make every `jsonb` hash column `null: false, default: {}`
- make array-shaped draft refs `null: false, default: []`
- set obvious counters to `null: false, default: 0`
- set `active` booleans to `null: false, default: true`
- add composite indexes now, not later
- add explicit foreign keys for every aliased or self-referential `*_id:bigint`
- keep `conversations.root_conversation_id` nullable in v1 and set it immediately after root creation inside the service transaction

### Foreign Keys To Add Manually

Use `add_foreign_key` in the migration after each `create_table` block where needed.

- `conversations.parent_conversation_id -> conversations`
- `conversations.root_conversation_id -> conversations`
- `conversations.branched_from_message_id -> conversation_messages`
- `conversations.branched_from_turn_id -> conversation_turns`
- `conversations.latest_turn_id -> conversation_turns`
- `conversations.latest_message_id -> conversation_messages`
- `conversations.managed_by_subagent_run_id -> subagent_runs`
- `conversation_closures.ancestor_conversation_id -> conversations`
- `conversation_closures.descendant_conversation_id -> conversations`
- `conversation_turns.blocked_by_turn_id -> conversation_turns`
- `conversation_turns.selected_input_message_id -> conversation_messages`
- `conversation_turns.selected_output_message_id -> conversation_messages`
- `conversation_messages.replaces_message_id -> conversation_messages`
- `message_attachments.origin_message_attachment_id -> message_attachments`
- `message_attachments.origin_message_id -> conversation_messages`
- `message_attachments.origin_conversation_id -> conversations`
- `conversation_imports.target_conversation_id -> conversations`
- `conversation_imports.source_conversation_id -> conversations`
- `conversation_imports.source_message_id -> conversation_messages`
- `conversation_imports.summary_message_id -> conversation_messages`
- `conversation_summary_segments.summary_message_id -> conversation_messages`
- `conversation_summary_segments.replaces_segment_id -> conversation_summary_segments`
- `turn_workflows.terminal_node_id -> workflow_nodes`
- `workflow_edges.from_node_id -> workflow_nodes`
- `workflow_edges.to_node_id -> workflow_nodes`
- `subagent_runs.child_conversation_id -> conversations`
- `subagent_runs.result_artifact_id -> workflow_artifacts`
- `process_runs.log_artifact_id -> workflow_artifacts`
- `workspace_documents.latest_revision_id -> workspace_document_revisions`
- `workspace_document_revisions.workflow_artifact_id -> workflow_artifacts`

Deletion semantics:

- structural links should keep the default restrictive behavior:
  - `parent_conversation_id`
  - `root_conversation_id`
  - `target_conversation_id`
  - `source_conversation_id`
- optional pointer links should use `on_delete: :nullify`:
  - latest / selected / origin / artifact / managed-by pointers

### High-Value Indexes To Add Immediately

- unique `conversations.public_id`
- index `conversations.agent_id, latest_activity_at`
- index `conversations.parent_conversation_id, branch_position`
- index `conversations.root_conversation_id, latest_activity_at`
- unique `conversation_closures.ancestor_conversation_id, descendant_conversation_id`
- unique `conversation_turns.conversation_id, sequence`
- index `conversation_turns.conversation_id, status, queue_position`
- unique `conversation_messages.public_id`
- index `conversation_messages.conversation_turn_id, slot, created_at`
- unique `conversation_message_visibilities.conversation_message_id`
- index `message_attachments.conversation_message_id, position`
- index `conversation_imports.target_conversation_id, position`
- index `conversation_summary_segments.conversation_id, status`
- unique `turn_workflows.public_id`
- unique `turn_workflows.conversation_turn_id`
- unique `workflow_nodes.public_id`
- unique `workflow_nodes.turn_workflow_id, ordinal`
- unique `workflow_nodes.turn_workflow_id, key` where `key` is not null
- unique `workflow_edges.from_node_id, to_node_id`
- index `workflow_node_events.turn_workflow_id, workflow_node_id, kind, id`
- unique `subagent_runs.public_id`
- unique `process_runs.public_id`
- index `process_runs.conversation_id, kind, status`
- unique `execution_leases.subject_type, subject_id, execution_request_key`
- unique `conversation_drafts.conversation_id`
- index `tool_permission_grants.subject_type, subject_id, tool_name, status`
- unique `workspace_documents.conversation_id, path, conversation_scope`
- index `tool_call_facts.tool_name, created_at`

### Bootstrap Refinement From The Conceptual Design

For the first implementation pass, keep these two Rails-native refinements:

- `MessageAttachment` should use `has_one_attached :file` instead of persisting `active_storage_attachment_id`
- `WorkflowArtifact` should use `has_one_attached :file` when `storage_mode == "active_storage"`

This is cleaner in a greenfield Rails app and removes manual attachment-row bookkeeping from day one.

## Model Skeletons

These are intentionally thin. They are enough to start wiring services and tests without baking business logic into the wrong layer.

### Tree And Transcript

```ruby
# app/models/agent.rb
class Agent < ApplicationRecord
  has_many :conversations, dependent: :restrict_with_exception
  has_many :conversation_drafts, foreign_key: :selected_agent_id, dependent: :nullify

  enum :status, { active: "active", archived: "archived" }, validate: true
end

# app/models/conversation.rb
class Conversation < ApplicationRecord
  belongs_to :agent
  belongs_to :parent_conversation, class_name: "Conversation", optional: true
  belongs_to :root_conversation, class_name: "Conversation", optional: true
  belongs_to :branched_from_message, class_name: "ConversationMessage", optional: true
  belongs_to :branched_from_turn, class_name: "ConversationTurn", optional: true
  belongs_to :latest_turn, class_name: "ConversationTurn", optional: true
  belongs_to :latest_message, class_name: "ConversationMessage", optional: true
  belongs_to :managed_by_subagent_run, class_name: "SubagentRun", optional: true

  has_many :child_conversations, class_name: "Conversation", foreign_key: :parent_conversation_id, dependent: :restrict_with_exception
  has_many :turns, class_name: "ConversationTurn", dependent: :destroy
  has_many :messages, through: :turns
  has_many :imports, class_name: "ConversationImport", foreign_key: :target_conversation_id, dependent: :destroy
  has_many :summary_segments, class_name: "ConversationSummarySegment", dependent: :destroy
  has_one :draft, class_name: "ConversationDraft", dependent: :destroy

  enum :status, { active: "active", archived: "archived", closed: "closed" }, validate: true

  def root?
    parent_conversation_id.nil?
  end

  def managed_read_only?
    managed_by_subagent_run_id.present?
  end
end

# app/models/conversation_closure.rb
class ConversationClosure < ApplicationRecord
  belongs_to :ancestor_conversation, class_name: "Conversation"
  belongs_to :descendant_conversation, class_name: "Conversation"
end

# app/models/conversation_turn.rb
class ConversationTurn < ApplicationRecord
  belongs_to :conversation
  belongs_to :blocked_by_turn, class_name: "ConversationTurn", optional: true
  belongs_to :selected_input_message, class_name: "ConversationMessage", optional: true
  belongs_to :selected_output_message, class_name: "ConversationMessage", optional: true

  has_many :messages, class_name: "ConversationMessage", dependent: :destroy
  has_one :workflow, class_name: "TurnWorkflow", dependent: :destroy

  enum :trigger_kind, {
    user: "user",
    system: "system",
    automation: "automation",
    subagent_callback: "subagent_callback",
    merge: "merge"
  }, validate: true

  enum :status, {
    draft: "draft",
    queued: "queued",
    running: "running",
    awaiting_approval: "awaiting_approval",
    finished: "finished",
    errored: "errored",
    stopped: "stopped"
  }, validate: true
end

# app/models/conversation_message.rb
class ConversationMessage < ApplicationRecord
  belongs_to :conversation
  belongs_to :conversation_turn
  belongs_to :replaces_message, class_name: "ConversationMessage", optional: true

  has_one :visibility, class_name: "ConversationMessageVisibility", dependent: :destroy
  has_many :attachments, class_name: "MessageAttachment", dependent: :destroy

  enum :role, {
    system: "system",
    developer: "developer",
    user: "user",
    assistant: "assistant",
    character: "character",
    summary: "summary"
  }, validate: true

  enum :slot, {
    turn_input: "turn_input",
    turn_output: "turn_output",
    import_summary: "import_summary",
    note: "note"
  }, validate: true
end

# app/models/conversation_message_visibility.rb
class ConversationMessageVisibility < ApplicationRecord
  belongs_to :conversation_message

  delegate :conversation, to: :conversation_message
end

# app/models/message_attachment.rb
class MessageAttachment < ApplicationRecord
  belongs_to :conversation
  belongs_to :conversation_message
  belongs_to :origin_message_attachment, class_name: "MessageAttachment", optional: true
  belongs_to :origin_message, class_name: "ConversationMessage", optional: true
  belongs_to :origin_conversation, class_name: "Conversation", optional: true

  has_one_attached :file

  enum :kind, { file: "file", image: "image", screenshot: "screenshot", artifact: "artifact" }, validate: true
  enum :preparation_status, { pending: "pending", prepared: "prepared", failed: "failed" }, validate: true
end

# app/models/conversation_import.rb
class ConversationImport < ApplicationRecord
  belongs_to :target_conversation, class_name: "Conversation"
  belongs_to :source_conversation, class_name: "Conversation"
  belongs_to :source_message, class_name: "ConversationMessage", optional: true
  belongs_to :summary_message, class_name: "ConversationMessage", optional: true

  enum :kind, {
    branch_prefix: "branch_prefix",
    merge_summary: "merge_summary",
    quoted_context: "quoted_context"
  }, validate: true
end

# app/models/conversation_summary_segment.rb
class ConversationSummarySegment < ApplicationRecord
  belongs_to :conversation
  belongs_to :summary_message, class_name: "ConversationMessage"
  belongs_to :replaces_segment, class_name: "ConversationSummarySegment", optional: true

  enum :kind, {
    auto_compaction: "auto_compaction",
    manual_summary: "manual_summary",
    merge_summary: "merge_summary"
  }, validate: true

  enum :status, { active: "active", superseded: "superseded" }, validate: true
end
```

### Workflow

```ruby
# app/models/turn_workflow.rb
class TurnWorkflow < ApplicationRecord
  belongs_to :conversation_turn
  belongs_to :terminal_node, class_name: "WorkflowNode", optional: true

  has_many :nodes, class_name: "WorkflowNode", dependent: :destroy
  has_many :edges, class_name: "WorkflowEdge", dependent: :destroy
  has_many :events, through: :nodes, source: :events
  has_many :artifacts, through: :nodes, source: :artifacts
  has_many :approval_requests, through: :nodes, source: :approval_requests

  enum :status, {
    draft: "draft",
    running: "running",
    awaiting_approval: "awaiting_approval",
    finished: "finished",
    failed: "failed",
    rejected: "rejected",
    stopped: "stopped"
  }, validate: true
end

# app/models/workflow_node.rb
class WorkflowNode < ApplicationRecord
  belongs_to :turn_workflow

  has_many :incoming_edges, class_name: "WorkflowEdge", foreign_key: :to_node_id, dependent: :destroy, inverse_of: :to_node
  has_many :outgoing_edges, class_name: "WorkflowEdge", foreign_key: :from_node_id, dependent: :destroy, inverse_of: :from_node
  has_many :events, class_name: "WorkflowNodeEvent", dependent: :destroy
  has_many :artifacts, class_name: "WorkflowArtifact", dependent: :destroy
  has_many :subagent_runs, dependent: :destroy
  has_many :process_runs, dependent: :destroy
  has_many :approval_requests, dependent: :destroy

  enum :node_type, {
    model_step: "model_step",
    tool_call: "tool_call",
    command_exec: "command_exec",
    subagent_run: "subagent_run",
    join: "join",
    approval_gate: "approval_gate",
    finalize: "finalize",
    summary: "summary"
  }, validate: true

  enum :state, {
    ready: "ready",
    blocked: "blocked",
    running: "running",
    awaiting_approval: "awaiting_approval",
    finished: "finished",
    failed: "failed",
    rejected: "rejected",
    skipped: "skipped",
    canceled: "canceled",
    timed_out: "timed_out"
  }, validate: true
end

# app/models/workflow_edge.rb
class WorkflowEdge < ApplicationRecord
  belongs_to :turn_workflow
  belongs_to :from_node, class_name: "WorkflowNode"
  belongs_to :to_node, class_name: "WorkflowNode"
end

# app/models/workflow_node_event.rb
class WorkflowNodeEvent < ApplicationRecord
  belongs_to :turn_workflow
  belongs_to :workflow_node

  enum :kind, {
    status_changed: "status_changed",
    activity: "activity",
    output_delta: "output_delta",
    approval_requested: "approval_requested",
    approval_resolved: "approval_resolved",
    diagnostic: "diagnostic",
    resource_linked: "resource_linked"
  }, validate: true
end

# app/models/workflow_artifact.rb
class WorkflowArtifact < ApplicationRecord
  belongs_to :turn_workflow
  belongs_to :workflow_node

  has_one_attached :file

  enum :storage_mode, {
    inline_json: "inline_json",
    active_storage: "active_storage",
    foreign_reference: "foreign_reference",
    external_url: "external_url"
  }, validate: true
end
```

### Resources And Control Plane

```ruby
# app/models/subagent_run.rb
class SubagentRun < ApplicationRecord
  belongs_to :workflow_node
  belongs_to :turn_workflow
  belongs_to :conversation_turn
  belongs_to :conversation
  belongs_to :child_conversation, class_name: "Conversation", optional: true
  belongs_to :result_artifact, class_name: "WorkflowArtifact", optional: true

  enum :status, {
    starting: "starting",
    running: "running",
    waiting: "waiting",
    succeeded: "succeeded",
    failed: "failed",
    killed: "killed",
    timed_out: "timed_out",
    lost: "lost",
    closed: "closed"
  }, validate: true

  enum :management_mode, {
    managed: "managed",
    read_only_external: "read_only_external"
  }, validate: true
end

# app/models/process_run.rb
class ProcessRun < ApplicationRecord
  belongs_to :workflow_node
  belongs_to :turn_workflow
  belongs_to :conversation_turn
  belongs_to :conversation
  belongs_to :log_artifact, class_name: "WorkflowArtifact", optional: true

  enum :kind, { turn_command: "turn_command", background_service: "background_service" }, validate: true
  enum :started_by_type, { agent: "agent", user: "user" }, validate: true

  enum :status, {
    starting: "starting",
    running: "running",
    succeeded: "succeeded",
    failed: "failed",
    killed: "killed",
    timed_out: "timed_out",
    lost: "lost",
    closed: "closed"
  }, validate: true
end

# app/models/approval_request.rb
class ApprovalRequest < ApplicationRecord
  belongs_to :workflow_node
  belongs_to :turn_workflow

  enum :status, {
    pending: "pending",
    approved: "approved",
    denied: "denied",
    expired: "expired",
    canceled: "canceled"
  }, validate: true
end

# app/models/execution_lease.rb
class ExecutionLease < ApplicationRecord
  enum :status, { active: "active", released: "released", expired: "expired" }, validate: true
end
```

### Support And Projections

```ruby
# app/models/conversation_draft.rb
class ConversationDraft < ApplicationRecord
  belongs_to :conversation
  belongs_to :selected_agent, class_name: "Agent", optional: true
end

# app/models/tool_permission_grant.rb
class ToolPermissionGrant < ApplicationRecord
  enum :status, { active: "active", revoked: "revoked", expired: "expired" }, validate: true
end

# app/models/workspace_document.rb
class WorkspaceDocument < ApplicationRecord
  belongs_to :conversation, optional: true
  belongs_to :latest_revision, class_name: "WorkspaceDocumentRevision", optional: true

  has_many :revisions, class_name: "WorkspaceDocumentRevision", dependent: :destroy
end

# app/models/workspace_document_revision.rb
class WorkspaceDocumentRevision < ApplicationRecord
  belongs_to :workspace_document
  belongs_to :workflow_artifact, optional: true
end

# app/models/tool_call_fact.rb
class ToolCallFact < ApplicationRecord
  belongs_to :conversation
  belongs_to :conversation_turn
  belongs_to :turn_workflow
  belongs_to :workflow_node

  enum :execution_scope, { parent: "parent", subagent: "subagent" }, validate: true
end
```

## Suggested First Implementation Order After Schema

Build in this order:

1. `Conversation`, `ConversationClosure`, `ConversationTurn`, `ConversationMessage`
2. `ConversationDraft`, `MessageAttachment`, `ConversationImport`
3. `TurnWorkflow`, `WorkflowNode`, `WorkflowEdge`
4. `WorkflowNodeEvent`, `WorkflowArtifact`
5. `SubagentRun`, `ProcessRun`, `ApprovalRequest`, `ExecutionLease`
6. `WorkspaceDocument`, `WorkspaceDocumentRevision`, `ToolPermissionGrant`
7. `ToolCallFact`
8. application services
9. query objects
10. stop and hand off to the follow-up document for UI/runtime work

The reason for this order:

- tree and transcript unblock the first visible product loop
- workflow models unblock tool/subagent execution
- resource models unblock safety and control-plane semantics
- projection models can lag behind truth models

## First Tests To Write

Write these before filling in service logic:

1. conversation tree creation and closure-row maintenance
2. branch creation with inherited prefix import
3. queued follow-up turn creation while a run is active
4. steer-current-input blocked after first side effect
5. workflow edge invariant: lower ordinal to higher ordinal only
6. parallel child nodes joining into one finalize path
7. subagent child conversation stays owner-managed read-only
8. turn command timeout kills the process group and records terminal reason
9. approval request pauses and resumes the owning workflow node safely
10. tool-call fact projection records parent vs subagent scope

## Concrete First Service Set

Create these files next, even if the classes are initially empty:

```ruby
# app/services/conversations/create_root.rb
module Conversations
  class CreateRoot
  end
end

# app/services/conversations/create_branch.rb
module Conversations
  class CreateBranch
  end
end

# app/services/turns/start_user_turn.rb
module Turns
  class StartUserTurn
  end
end

# app/services/turns/queue_follow_up.rb
module Turns
  class QueueFollowUp
  end
end

# app/services/turns/steer_current_input.rb
module Turns
  class SteerCurrentInput
  end
end

# app/services/workflows/mutator.rb
module Workflows
  class Mutator
  end
end

# app/services/workflows/scheduler.rb
module Workflows
  class Scheduler
  end
end

# app/services/subagents/spawn.rb
module Subagents
  class Spawn
  end
end

# app/services/processes/start.rb
module Processes
  class Start
  end
end
```

## Coverage Check Against Current Cybros

This bootstrap explicitly accounts for features that are easy to miss if you only look at the older DAG docs:

- historical message branch with reusable attachments
- inherited read-only branch prefix
- queued follow-up input while a run is active
- steer-current-turn before side effects
- subagent owner-managed child conversations
- subagent poll / wait / close control plane
- live turn-command streaming in the composer rail
- detached background processes as a separate `ProcessRun.kind`
- persisted approval state and resume-safe execution facts
- explicit execution leases instead of implicit ownership only
- tool reliability / execution-scope projections

This document intentionally does not cover:

- controllers or request/response contracts
- Action Cable or other realtime transport choices
- views, presenters, or JavaScript UI state
- background job orchestration details
- provider/runtime adapter implementation

## Self-Review

This bootstrap is intentionally stricter than a naive `rails generate model` dump.

- It avoids unsafe aliased `references` usage.
- It keeps the global conversation model as a tree, not a graph.
- It keeps DAG overhead local to `TurnWorkflow`.
- It fixes v1 defaults now instead of leaving them as open design questions.
- It includes the newer Cybros capabilities that showed up in recent rescans:
  - subagent thread control plane
  - historical attachment reuse
  - turn-scoped exec streaming
  - queued/steered turn input
  - execution capacity leases
- It stays Rails-first by letting Active Storage own file attachments directly.

## Source References

- [The Rails Command Line](https://guides.rubyonrails.org/command_line.html)
- [Active Storage Overview](https://guides.rubyonrails.org/active_storage_overview.html)
