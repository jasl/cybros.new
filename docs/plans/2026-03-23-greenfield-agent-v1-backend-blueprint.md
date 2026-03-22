# Greenfield Agent V1 Backend Blueprint

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Provide implementation-ready Rails backend code guidance for the `core_matrix` implementation of the greenfield agent design, covering migrations, models, and backend-first tests for v1.

**Architecture:** Use a conversation tree plus append-only transcript for user-visible history, and a per-turn workflow DAG for execution. Keep control-plane state in explicit Active Record models and defer all controller/UI/realtime/runtime-adapter work in v1 to [CoreMatrix Agent UI And Runtime Follow-Up](./2026-03-23-core-matrix-agent-ui-runtime-follow-up.md).

**Tech Stack:** Rails 8.2 defaults, PostgreSQL, Active Storage, Minitest.

---

## Official Rails References

These are the primary references this blueprint follows:

- [Active Record Migrations](https://guides.rubyonrails.org/active_record_migrations.html)
- [Active Record Basics](https://guides.rubyonrails.org/active_record_basics.html)
- [Active Storage Overview](https://guides.rubyonrails.org/active_storage_overview.html)
- [Testing Rails Applications](https://guides.rubyonrails.org/testing.html)
- [Active Record and PostgreSQL](https://guides.rubyonrails.org/active_record_postgresql.html)

Implementation choices aligned to those guides:

- prefer conventional association names when possible
- use `add_foreign_key` for aliased/self-referential columns
- keep database constraints and indexes explicit in migrations
- use `has_one_attached` for file-bearing records
- use `ActiveSupport::TestCase` model/service tests under `test/`
- in the actual implementation, finite state fields should use string-backed Rails enums consistently

## V1 Scope

This blueprint is intentionally backend-only.

- implement inside the existing `core_matrix` app
- build migrations
- build models
- build backend tests
- do not build controllers, channels, views, or UI state in this slice
- do not build background job orchestration or provider/runtime adapters in this slice

This is the minimum safe slice for later UI/runtime implementation.

## Shared Support Files

Create the concern before the model files. Add the record builders immediately before the first model and service tests.

### `/app/models/concerns/has_public_id.rb`

```ruby
module HasPublicId
  extend ActiveSupport::Concern

  included do
    before_validation :assign_public_id, on: :create

    validates :public_id, presence: true, uniqueness: true
  end

  private

  def assign_public_id
    self.public_id ||= SecureRandom.uuid
  end
end
```

### `/test/support/record_builders.rb`

```ruby
module RecordBuilders
  def build_agent(attributes = {})
    Agent.create!(
      {
        name: "Main agent",
        status: "active",
        runtime_kind: "codex_like",
        tool_policy_mode: "default",
        default_timeout_s: 300,
        config: {}
      }.merge(attributes)
    )
  end

  def build_root_conversation(agent:, attributes: {})
    conversation = Conversation.create!(
      {
        agent: agent,
        title: "Root",
        status: "active",
        depth: 0,
        branch_position: 0,
        children_count: 0,
        metadata: {}
      }.merge(attributes)
    )
    conversation.update_column(:root_conversation_id, conversation.id)
    ConversationClosure.create!(
      ancestor_conversation: conversation,
      descendant_conversation: conversation,
      depth: 0
    )
    conversation.reload
  end

  def build_turn(conversation:, attributes: {})
    ConversationTurn.create!(
      {
        conversation: conversation,
        sequence: conversation.turns.maximum(:sequence).to_i + 1,
        trigger_kind: "user",
        status: "draft",
        metadata: {}
      }.merge(attributes)
    )
  end

  def build_message(conversation:, turn:, attributes: {})
    ConversationMessage.create!(
      {
        conversation: conversation,
        conversation_turn: turn,
        role: "user",
        slot: "turn_input",
        variant_kind: "canonical",
        content_markdown: "hello",
        structured_content: {},
        metadata: {},
        usage_payload: {}
      }.merge(attributes)
    )
  end
end
```

### `/test/test_helper.rb`

Add:

```ruby
require_relative "support/record_builders"

class ActiveSupport::TestCase
  include RecordBuilders
end
```

## Migration Files

Before applying the domain migrations below in `core_matrix`, ensure the Active Storage installation migration already exists and has been applied.

Use migration version matching `core_matrix`. The examples below assume `ActiveRecord::Migration[8.2]`.

### `db/migrate/xxxxxx_create_agents.rb`

```ruby
class CreateAgents < ActiveRecord::Migration[8.2]
  def change
    create_table :agents do |t|
      t.string :public_id, null: false
      t.string :name, null: false
      t.string :status, null: false
      t.string :runtime_kind, null: false
      t.integer :default_timeout_s
      t.string :tool_policy_mode, null: false
      t.jsonb :config, null: false, default: {}
      t.timestamps
    end

    add_index :agents, :public_id, unique: true
    add_index :agents, [:status, :runtime_kind]
  end
end
```

### `db/migrate/xxxxxx_create_conversations.rb`

```ruby
class CreateConversations < ActiveRecord::Migration[8.2]
  def change
    create_table :conversations do |t|
      t.string :public_id, null: false
      t.references :agent, null: false, foreign_key: true
      t.string :title, null: false
      t.string :status, null: false
      t.bigint :parent_conversation_id
      t.bigint :root_conversation_id
      t.bigint :branched_from_message_id
      t.bigint :branched_from_turn_id
      t.integer :depth, null: false, default: 0
      t.integer :branch_position, null: false, default: 0
      t.integer :children_count, null: false, default: 0
      t.bigint :latest_turn_id
      t.bigint :latest_message_id
      t.bigint :managed_by_subagent_run_id
      t.datetime :latest_activity_at
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end

    add_index :conversations, :public_id, unique: true
    add_index :conversations, [:agent_id, :latest_activity_at]
    add_index :conversations, [:parent_conversation_id, :branch_position]
    add_index :conversations, [:root_conversation_id, :latest_activity_at]
    add_index :conversations, :managed_by_subagent_run_id

    add_foreign_key :conversations, :conversations, column: :parent_conversation_id
    add_foreign_key :conversations, :conversations, column: :root_conversation_id
  end
end
```

### `db/migrate/xxxxxx_create_conversation_closures.rb`

```ruby
class CreateConversationClosures < ActiveRecord::Migration[8.2]
  def change
    create_table :conversation_closures do |t|
      t.bigint :ancestor_conversation_id, null: false
      t.bigint :descendant_conversation_id, null: false
      t.integer :depth, null: false
      t.timestamps
    end

    add_index :conversation_closures,
      [:ancestor_conversation_id, :descendant_conversation_id],
      unique: true,
      name: "index_conversation_closures_uniqueness"
    add_index :conversation_closures, [:descendant_conversation_id, :depth]
    add_index :conversation_closures, [:ancestor_conversation_id, :depth]

    add_foreign_key :conversation_closures, :conversations, column: :ancestor_conversation_id
    add_foreign_key :conversation_closures, :conversations, column: :descendant_conversation_id
  end
end
```

### `db/migrate/xxxxxx_create_conversation_turns.rb`

```ruby
class CreateConversationTurns < ActiveRecord::Migration[8.2]
  def change
    create_table :conversation_turns do |t|
      t.string :public_id, null: false
      t.references :conversation, null: false, foreign_key: true
      t.integer :sequence, null: false
      t.string :trigger_kind, null: false
      t.string :status, null: false
      t.integer :queue_position
      t.bigint :blocked_by_turn_id
      t.bigint :selected_input_message_id
      t.bigint :selected_output_message_id
      t.datetime :queued_at
      t.datetime :started_at
      t.datetime :finished_at
      t.datetime :latest_activity_at
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end

    add_index :conversation_turns, :public_id, unique: true
    add_index :conversation_turns, [:conversation_id, :sequence], unique: true
    add_index :conversation_turns, [:conversation_id, :status, :queue_position]
    add_index :conversation_turns, [:conversation_id, :latest_activity_at]

    add_foreign_key :conversation_turns, :conversation_turns, column: :blocked_by_turn_id
  end
end
```

### `db/migrate/xxxxxx_create_conversation_messages.rb`

```ruby
class CreateConversationMessages < ActiveRecord::Migration[8.2]
  def change
    create_table :conversation_messages do |t|
      t.string :public_id, null: false
      t.references :conversation, null: false, foreign_key: true
      t.references :conversation_turn, null: false, foreign_key: true
      t.string :role, null: false
      t.string :slot, null: false
      t.string :variant_kind, null: false
      t.bigint :replaces_message_id
      t.text :content_markdown
      t.jsonb :structured_content, null: false, default: {}
      t.jsonb :metadata, null: false, default: {}
      t.integer :tokens_input
      t.integer :tokens_output
      t.jsonb :usage_payload, null: false, default: {}
      t.timestamps
    end

    add_index :conversation_messages, :public_id, unique: true
    add_index :conversation_messages, [:conversation_id, :conversation_turn_id, :created_at], name: "index_messages_on_conversation_turn_created_at"
    add_index :conversation_messages, [:conversation_turn_id, :slot, :created_at]
    add_index :conversation_messages, :replaces_message_id

    add_foreign_key :conversation_messages, :conversation_messages, column: :replaces_message_id
  end
end
```

### `db/migrate/xxxxxx_add_turn_message_foreign_keys.rb`

```ruby
class AddTurnMessageForeignKeys < ActiveRecord::Migration[8.2]
  def change
    add_foreign_key :conversation_turns, :conversation_messages, column: :selected_input_message_id, on_delete: :nullify
    add_foreign_key :conversation_turns, :conversation_messages, column: :selected_output_message_id, on_delete: :nullify

    add_foreign_key :conversations, :conversation_messages, column: :branched_from_message_id, on_delete: :nullify
    add_foreign_key :conversations, :conversation_messages, column: :latest_message_id, on_delete: :nullify
    add_foreign_key :conversations, :conversation_turns, column: :branched_from_turn_id, on_delete: :nullify
    add_foreign_key :conversations, :conversation_turns, column: :latest_turn_id, on_delete: :nullify
  end
end
```

### `db/migrate/xxxxxx_create_conversation_message_visibilities.rb`

```ruby
class CreateConversationMessageVisibilities < ActiveRecord::Migration[8.2]
  def change
    create_table :conversation_message_visibilities do |t|
      t.references :conversation_message, null: false, foreign_key: true
      t.datetime :deleted_at
      t.datetime :context_excluded_at
      t.datetime :hidden_at
      t.string :hidden_reason
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end

    add_index :conversation_message_visibilities, :conversation_message_id, unique: true, name: "index_message_visibilities_uniqueness"
    add_index :conversation_message_visibilities, :deleted_at
    add_index :conversation_message_visibilities, :context_excluded_at
  end
end
```

### `db/migrate/xxxxxx_create_message_attachments.rb`

```ruby
class CreateMessageAttachments < ActiveRecord::Migration[8.2]
  def change
    create_table :message_attachments do |t|
      t.references :conversation, null: false, foreign_key: true
      t.references :conversation_message, null: false, foreign_key: true
      t.integer :position, null: false
      t.string :kind, null: false
      t.bigint :origin_message_attachment_id
      t.bigint :origin_message_id
      t.bigint :origin_conversation_id
      t.string :preparation_status, null: false
      t.jsonb :preparation_ref, null: false, default: {}
      t.string :sha256_digest
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end

    add_index :message_attachments, [:conversation_message_id, :position], unique: true
    add_index :message_attachments, [:conversation_id, :preparation_status]
    add_index :message_attachments, :origin_message_id

    add_foreign_key :message_attachments, :message_attachments, column: :origin_message_attachment_id, on_delete: :nullify
    add_foreign_key :message_attachments, :conversation_messages, column: :origin_message_id, on_delete: :nullify
    add_foreign_key :message_attachments, :conversations, column: :origin_conversation_id, on_delete: :nullify
  end
end
```

### `db/migrate/xxxxxx_create_conversation_imports.rb`

```ruby
class CreateConversationImports < ActiveRecord::Migration[8.2]
  def change
    create_table :conversation_imports do |t|
      t.bigint :target_conversation_id, null: false
      t.bigint :source_conversation_id, null: false
      t.string :kind, null: false
      t.string :mode, null: false
      t.integer :position, null: false
      t.bigint :source_message_id
      t.integer :source_start_turn_sequence
      t.integer :source_end_turn_sequence
      t.bigint :summary_message_id
      t.boolean :active, null: false, default: true
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end

    add_index :conversation_imports, [:target_conversation_id, :position]
    add_index :conversation_imports, :source_conversation_id
    add_index :conversation_imports, :active

    add_foreign_key :conversation_imports, :conversations, column: :target_conversation_id
    add_foreign_key :conversation_imports, :conversations, column: :source_conversation_id
    add_foreign_key :conversation_imports, :conversation_messages, column: :source_message_id, on_delete: :nullify
    add_foreign_key :conversation_imports, :conversation_messages, column: :summary_message_id, on_delete: :nullify
  end
end
```

### `db/migrate/xxxxxx_create_conversation_summary_segments.rb`

```ruby
class CreateConversationSummarySegments < ActiveRecord::Migration[8.2]
  def change
    create_table :conversation_summary_segments do |t|
      t.references :conversation, null: false, foreign_key: true
      t.string :kind, null: false
      t.string :status, null: false
      t.integer :start_turn_sequence, null: false
      t.integer :end_turn_sequence, null: false
      t.bigint :summary_message_id, null: false
      t.bigint :replaces_segment_id
      t.integer :token_estimate
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end

    add_index :conversation_summary_segments, [:conversation_id, :start_turn_sequence, :end_turn_sequence], name: "index_summary_segments_on_turn_window"
    add_index :conversation_summary_segments, [:conversation_id, :status]

    add_foreign_key :conversation_summary_segments, :conversation_messages, column: :summary_message_id
    add_foreign_key :conversation_summary_segments, :conversation_summary_segments, column: :replaces_segment_id
  end
end
```

### `db/migrate/xxxxxx_create_turn_workflows.rb`

```ruby
class CreateTurnWorkflows < ActiveRecord::Migration[8.2]
  def change
    create_table :turn_workflows do |t|
      t.string :public_id, null: false
      t.references :conversation_turn, null: false, foreign_key: true
      t.string :status, null: false
      t.string :planner_mode, null: false
      t.bigint :next_ordinal, null: false, default: 1
      t.integer :ready_nodes_count, null: false, default: 0
      t.integer :running_nodes_count, null: false, default: 0
      t.integer :awaiting_approval_count, null: false, default: 0
      t.integer :active_resource_count, null: false, default: 0
      t.bigint :terminal_node_id
      t.datetime :started_at
      t.datetime :finished_at
      t.datetime :last_activity_at
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end

    add_index :turn_workflows, :public_id, unique: true
    add_index :turn_workflows, :conversation_turn_id, unique: true
    add_index :turn_workflows, [:status, :last_activity_at]
  end
end
```

### `db/migrate/xxxxxx_create_workflow_nodes.rb`

```ruby
class CreateWorkflowNodes < ActiveRecord::Migration[8.2]
  def change
    create_table :workflow_nodes do |t|
      t.string :public_id, null: false
      t.references :turn_workflow, null: false, foreign_key: true
      t.bigint :ordinal, null: false
      t.string :node_type, null: false
      t.string :state, null: false
      t.string :key
      t.integer :attempt, null: false, default: 1
      t.string :join_policy
      t.string :reducer_type
      t.integer :required_inputs_total, null: false, default: 0
      t.integer :required_inputs_finished, null: false, default: 0
      t.integer :optional_inputs_total, null: false, default: 0
      t.integer :optional_inputs_finished, null: false, default: 0
      t.jsonb :input_payload, null: false, default: {}
      t.jsonb :output_payload, null: false, default: {}
      t.jsonb :error_payload, null: false, default: {}
      t.datetime :claimed_at
      t.string :claimed_by
      t.datetime :lease_expires_at
      t.datetime :heartbeat_at
      t.datetime :started_at
      t.datetime :finished_at
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end

    add_index :workflow_nodes, :public_id, unique: true
    add_index :workflow_nodes, [:turn_workflow_id, :ordinal], unique: true
    add_index :workflow_nodes, [:turn_workflow_id, :state, :lease_expires_at]
    add_index :workflow_nodes, [:turn_workflow_id, :node_type, :state]
    add_index :workflow_nodes, [:turn_workflow_id, :key], unique: true, where: "key IS NOT NULL", name: "index_workflow_nodes_on_turn_workflow_id_and_key_present"
  end
end
```

### `db/migrate/xxxxxx_add_turn_workflow_terminal_fk.rb`

```ruby
class AddTurnWorkflowTerminalFk < ActiveRecord::Migration[8.2]
  def change
    add_foreign_key :turn_workflows, :workflow_nodes, column: :terminal_node_id, on_delete: :nullify
  end
end
```

### `db/migrate/xxxxxx_create_workflow_edges.rb`

```ruby
class CreateWorkflowEdges < ActiveRecord::Migration[8.2]
  def change
    create_table :workflow_edges do |t|
      t.references :turn_workflow, null: false, foreign_key: true
      t.bigint :from_node_id, null: false
      t.bigint :to_node_id, null: false
      t.boolean :required, null: false, default: true
      t.string :group_key
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end

    add_index :workflow_edges, [:from_node_id, :to_node_id], unique: true
    add_index :workflow_edges, [:turn_workflow_id, :to_node_id, :required]
    add_index :workflow_edges, [:turn_workflow_id, :from_node_id]

    add_foreign_key :workflow_edges, :workflow_nodes, column: :from_node_id
    add_foreign_key :workflow_edges, :workflow_nodes, column: :to_node_id
  end
end
```

### `db/migrate/xxxxxx_create_workflow_node_events.rb`

```ruby
class CreateWorkflowNodeEvents < ActiveRecord::Migration[8.2]
  def change
    create_table :workflow_node_events do |t|
      t.references :turn_workflow, null: false, foreign_key: true
      t.references :workflow_node, null: false, foreign_key: true
      t.string :kind, null: false
      t.jsonb :payload, null: false, default: {}
      t.text :text
      t.timestamps
    end

    add_index :workflow_node_events, [:workflow_node_id, :id]
    add_index :workflow_node_events, [:turn_workflow_id, :id]
    add_index :workflow_node_events, [:turn_workflow_id, :workflow_node_id, :kind, :id], name: "index_workflow_node_events_feed"
  end
end
```

### `db/migrate/xxxxxx_create_workflow_artifacts.rb`

```ruby
class CreateWorkflowArtifacts < ActiveRecord::Migration[8.2]
  def change
    create_table :workflow_artifacts do |t|
      t.references :turn_workflow, null: false, foreign_key: true
      t.references :workflow_node, null: false, foreign_key: true
      t.string :kind, null: false
      t.string :storage_mode, null: false
      t.jsonb :payload, null: false, default: {}
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end

    add_index :workflow_artifacts, [:workflow_node_id, :kind]
    add_index :workflow_artifacts, [:turn_workflow_id, :kind]
  end
end
```

### `db/migrate/xxxxxx_create_subagent_runs.rb`

```ruby
class CreateSubagentRuns < ActiveRecord::Migration[8.2]
  def change
    create_table :subagent_runs do |t|
      t.string :public_id, null: false
      t.references :workflow_node, null: false, foreign_key: true
      t.references :turn_workflow, null: false, foreign_key: true
      t.references :conversation_turn, null: false, foreign_key: true
      t.references :conversation, null: false, foreign_key: true
      t.bigint :child_conversation_id
      t.string :external_session_ref
      t.string :status, null: false
      t.string :management_mode, null: false
      t.jsonb :latest_snapshot, null: false, default: {}
      t.bigint :result_artifact_id
      t.datetime :claimed_at
      t.datetime :lease_expires_at
      t.datetime :heartbeat_at
      t.datetime :started_at
      t.datetime :finished_at
      t.string :close_reason
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end

    add_index :subagent_runs, :public_id, unique: true
    add_index :subagent_runs, [:workflow_node_id, :started_at]
    add_index :subagent_runs, :child_conversation_id
    add_index :subagent_runs, [:status, :lease_expires_at]

    add_foreign_key :subagent_runs, :conversations, column: :child_conversation_id, on_delete: :nullify
    add_foreign_key :subagent_runs, :workflow_artifacts, column: :result_artifact_id, on_delete: :nullify
  end
end
```

### `db/migrate/xxxxxx_create_process_runs.rb`

```ruby
class CreateProcessRuns < ActiveRecord::Migration[8.2]
  def change
    create_table :process_runs do |t|
      t.string :public_id, null: false
      t.references :workflow_node, null: false, foreign_key: true
      t.references :turn_workflow, null: false, foreign_key: true
      t.references :conversation_turn, null: false, foreign_key: true
      t.references :conversation, null: false, foreign_key: true
      t.string :kind, null: false
      t.string :status, null: false
      t.string :started_by_type, null: false
      t.string :title
      t.text :command, null: false
      t.text :cwd
      t.jsonb :env_preview, null: false, default: {}
      t.jsonb :port_hints, null: false, default: []
      t.text :log_path
      t.integer :pid
      t.integer :pgid
      t.bigint :log_artifact_id
      t.integer :timeout_s
      t.integer :exit_code
      t.string :terminal_reason
      t.datetime :claimed_at
      t.datetime :lease_expires_at
      t.datetime :heartbeat_at
      t.datetime :started_at
      t.datetime :finished_at
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end

    add_index :process_runs, :public_id, unique: true
    add_index :process_runs, [:workflow_node_id, :started_at]
    add_index :process_runs, [:conversation_turn_id, :status]
    add_index :process_runs, [:conversation_id, :kind, :status]
    add_index :process_runs, [:status, :lease_expires_at]

    add_foreign_key :process_runs, :workflow_artifacts, column: :log_artifact_id, on_delete: :nullify
  end
end
```

### `db/migrate/xxxxxx_create_approval_requests.rb`

```ruby
class CreateApprovalRequests < ActiveRecord::Migration[8.2]
  def change
    create_table :approval_requests do |t|
      t.references :workflow_node, null: false, foreign_key: true
      t.references :turn_workflow, null: false, foreign_key: true
      t.string :scope, null: false
      t.string :status, null: false
      t.jsonb :preview_payload, null: false, default: {}
      t.jsonb :decision_payload, null: false, default: {}
      t.string :resolved_by_actor_type
      t.bigint :resolved_by_actor_id
      t.datetime :resolved_at
      t.timestamps
    end

    add_index :approval_requests, [:workflow_node_id, :status]
    add_index :approval_requests, [:turn_workflow_id, :status]
  end
end
```

### `db/migrate/xxxxxx_create_execution_leases.rb`

```ruby
class CreateExecutionLeases < ActiveRecord::Migration[8.2]
  def change
    create_table :execution_leases do |t|
      t.string :subject_type, null: false
      t.bigint :subject_id, null: false
      t.string :holder_type, null: false
      t.bigint :holder_id, null: false
      t.string :execution_request_key, null: false
      t.integer :slots, null: false, default: 1
      t.string :status, null: false
      t.datetime :lease_expires_at, null: false
      t.datetime :heartbeat_at, null: false
      t.jsonb :recovery_metadata, null: false, default: {}
      t.timestamps
    end

    add_index :execution_leases, [:subject_type, :subject_id, :execution_request_key], unique: true, name: "index_execution_leases_uniqueness"
    add_index :execution_leases, [:holder_type, :holder_id, :status]
    add_index :execution_leases, [:status, :lease_expires_at]
  end
end
```

### `db/migrate/xxxxxx_create_conversation_drafts.rb`

```ruby
class CreateConversationDrafts < ActiveRecord::Migration[8.2]
  def change
    create_table :conversation_drafts do |t|
      t.references :conversation, null: false, foreign_key: true
      t.text :content_markdown
      t.references :selected_agent, foreign_key: { to_table: :agents }
      t.string :permission_mode
      t.jsonb :attachment_refs, null: false, default: []
      t.jsonb :metadata, null: false, default: {}
      t.string :updated_by_actor_type
      t.bigint :updated_by_actor_id
      t.timestamps
    end

    add_index :conversation_drafts, :conversation_id, unique: true
  end
end
```

### `db/migrate/xxxxxx_create_tool_permission_grants.rb`

```ruby
class CreateToolPermissionGrants < ActiveRecord::Migration[8.2]
  def change
    create_table :tool_permission_grants do |t|
      t.string :subject_type, null: false
      t.bigint :subject_id, null: false
      t.string :tool_name, null: false
      t.string :scope_kind, null: false
      t.string :pattern
      t.string :status, null: false
      t.string :granted_by_actor_type
      t.bigint :granted_by_actor_id
      t.datetime :expires_at
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end

    add_index :tool_permission_grants, [:subject_type, :subject_id, :tool_name, :status], name: "index_tool_permission_grants_lookup"
    add_index :tool_permission_grants, :expires_at
  end
end
```

### `db/migrate/xxxxxx_create_workspace_documents.rb`

```ruby
class CreateWorkspaceDocuments < ActiveRecord::Migration[8.2]
  def change
    create_table :workspace_documents do |t|
      t.references :conversation, foreign_key: true
      t.string :conversation_scope, null: false
      t.string :path, null: false
      t.string :title
      t.string :status, null: false
      t.bigint :latest_revision_id
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end

    add_index :workspace_documents, [:conversation_id, :path, :conversation_scope], unique: true, name: "index_workspace_documents_uniqueness"
    add_index :workspace_documents, [:conversation_id, :conversation_scope]
  end
end
```

### `db/migrate/xxxxxx_create_workspace_document_revisions.rb`

```ruby
class CreateWorkspaceDocumentRevisions < ActiveRecord::Migration[8.2]
  def change
    create_table :workspace_document_revisions do |t|
      t.references :workspace_document, null: false, foreign_key: true
      t.text :body_markdown, null: false
      t.string :source_kind, null: false
      t.bigint :workflow_artifact_id
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end

    add_index :workspace_document_revisions, [:workspace_document_id, :created_at]
    add_foreign_key :workspace_document_revisions, :workflow_artifacts, column: :workflow_artifact_id, on_delete: :nullify
  end
end
```

### `db/migrate/xxxxxx_add_workspace_documents_latest_revision_fk.rb`

```ruby
class AddWorkspaceDocumentsLatestRevisionFk < ActiveRecord::Migration[8.2]
  def change
    add_foreign_key :workspace_documents, :workspace_document_revisions, column: :latest_revision_id, on_delete: :nullify
  end
end
```

### `db/migrate/xxxxxx_create_tool_call_facts.rb`

```ruby
class CreateToolCallFacts < ActiveRecord::Migration[8.2]
  def change
    create_table :tool_call_facts do |t|
      t.references :conversation, null: false, foreign_key: true
      t.references :conversation_turn, null: false, foreign_key: true
      t.references :turn_workflow, null: false, foreign_key: true
      t.references :workflow_node, null: false, foreign_key: true
      t.string :tool_name, null: false
      t.string :tool_family
      t.string :execution_scope, null: false
      t.string :result_status, null: false
      t.string :failure_class
      t.string :approval_status
      t.integer :model_attempts, null: false, default: 0
      t.integer :tool_executions, null: false, default: 0
      t.integer :latency_ms
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end

    add_index :tool_call_facts, [:tool_name, :created_at]
    add_index :tool_call_facts, [:execution_scope, :result_status, :created_at]
    add_index :tool_call_facts, [:conversation_id, :created_at]
  end
end
```

### `db/migrate/xxxxxx_add_conversation_managed_subagent_fk.rb`

```ruby
class AddConversationManagedSubagentFk < ActiveRecord::Migration[8.2]
  def change
    add_foreign_key :conversations, :subagent_runs, column: :managed_by_subagent_run_id, on_delete: :nullify
  end
end
```

## Model Files

These are the recommended first-pass models. They follow Rails conventions and keep business orchestration out of the models.

### `app/models/agent.rb`

```ruby
class Agent < ApplicationRecord
  include HasPublicId

  STATUSES = %w[active archived].freeze

  has_many :conversations, dependent: :restrict_with_exception
  has_many :conversation_drafts, foreign_key: :selected_agent_id, dependent: :nullify

  validates :name, :status, :runtime_kind, :tool_policy_mode, presence: true
  validates :status, inclusion: { in: STATUSES }
end
```

### `app/models/conversation.rb`

```ruby
class Conversation < ApplicationRecord
  include HasPublicId

  STATUSES = %w[active archived closed].freeze

  belongs_to :agent
  belongs_to :parent_conversation, class_name: "Conversation", optional: true
  belongs_to :root_conversation, class_name: "Conversation", optional: true
  belongs_to :branched_from_message, class_name: "ConversationMessage", optional: true
  belongs_to :branched_from_turn, class_name: "ConversationTurn", optional: true
  belongs_to :latest_turn, class_name: "ConversationTurn", optional: true
  belongs_to :latest_message, class_name: "ConversationMessage", optional: true
  belongs_to :managed_by_subagent_run, class_name: "SubagentRun", optional: true

  has_many :child_conversations, class_name: "Conversation", foreign_key: :parent_conversation_id, dependent: :restrict_with_exception, inverse_of: :parent_conversation
  has_many :turns, class_name: "ConversationTurn", dependent: :destroy
  has_many :messages, through: :turns
  has_many :imports, class_name: "ConversationImport", foreign_key: :target_conversation_id, dependent: :destroy, inverse_of: :target_conversation
  has_many :summary_segments, class_name: "ConversationSummarySegment", dependent: :destroy
  has_one :draft, class_name: "ConversationDraft", dependent: :destroy

  validates :title, :status, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :depth, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :branch_position, :children_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  scope :roots, -> { where(parent_conversation_id: nil) }
  scope :recently_active, -> { order(latest_activity_at: :desc, id: :desc) }

  def root?
    parent_conversation_id.nil?
  end

  def managed_read_only?
    managed_by_subagent_run_id.present?
  end
end
```

### `app/models/conversation_closure.rb`

```ruby
class ConversationClosure < ApplicationRecord
  belongs_to :ancestor_conversation, class_name: "Conversation"
  belongs_to :descendant_conversation, class_name: "Conversation"

  validates :depth, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :ancestor_conversation_id, uniqueness: { scope: :descendant_conversation_id }
end
```

### `app/models/conversation_turn.rb`

```ruby
class ConversationTurn < ApplicationRecord
  include HasPublicId

  TRIGGER_KINDS = %w[user system automation subagent_callback merge].freeze
  STATUSES = %w[draft queued running awaiting_approval finished errored stopped].freeze

  belongs_to :conversation
  belongs_to :blocked_by_turn, class_name: "ConversationTurn", optional: true
  belongs_to :selected_input_message, class_name: "ConversationMessage", optional: true
  belongs_to :selected_output_message, class_name: "ConversationMessage", optional: true

  has_many :messages, class_name: "ConversationMessage", dependent: :destroy
  has_one :workflow, class_name: "TurnWorkflow", dependent: :destroy

  validates :sequence, presence: true, uniqueness: { scope: :conversation_id }
  validates :trigger_kind, presence: true, inclusion: { in: TRIGGER_KINDS }
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :queue_position, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true

  scope :ordered, -> { order(:sequence, :id) }
  scope :queued, -> { where(status: "queued").order(:queue_position, :id) }
  scope :active, -> { where(status: %w[queued running awaiting_approval]) }
end
```

### `app/models/conversation_message.rb`

```ruby
class ConversationMessage < ApplicationRecord
  include HasPublicId

  ROLES = %w[system developer user assistant character summary].freeze
  SLOTS = %w[turn_input turn_output import_summary note].freeze
  VARIANT_KINDS = %w[canonical rerun retry edit swipe imported].freeze

  belongs_to :conversation
  belongs_to :conversation_turn
  belongs_to :replaces_message, class_name: "ConversationMessage", optional: true

  has_one :visibility, class_name: "ConversationMessageVisibility", dependent: :destroy
  has_many :attachments, class_name: "MessageAttachment", dependent: :destroy

  validates :role, presence: true, inclusion: { in: ROLES }
  validates :slot, presence: true, inclusion: { in: SLOTS }
  validates :variant_kind, presence: true, inclusion: { in: VARIANT_KINDS }

  scope :chronological, -> { order(:created_at, :id) }
end
```

### `app/models/conversation_message_visibility.rb`

```ruby
class ConversationMessageVisibility < ApplicationRecord
  belongs_to :conversation_message

  validates :conversation_message_id, uniqueness: true

  delegate :conversation, :conversation_turn, to: :conversation_message
end
```

### `app/models/message_attachment.rb`

```ruby
class MessageAttachment < ApplicationRecord
  KINDS = %w[file image screenshot artifact].freeze
  PREPARATION_STATUSES = %w[pending prepared failed].freeze

  belongs_to :conversation
  belongs_to :conversation_message
  belongs_to :origin_message_attachment, class_name: "MessageAttachment", optional: true
  belongs_to :origin_message, class_name: "ConversationMessage", optional: true
  belongs_to :origin_conversation, class_name: "Conversation", optional: true

  has_one_attached :file

  validates :position, presence: true, numericality: { only_integer: true, greater_than: 0 }
  validates :kind, presence: true, inclusion: { in: KINDS }
  validates :preparation_status, presence: true, inclusion: { in: PREPARATION_STATUSES }
  validate :file_must_be_attached

  private

  def file_must_be_attached
    errors.add(:file, "must be attached") unless file.attached?
  end
end
```

### `app/models/conversation_import.rb`

```ruby
class ConversationImport < ApplicationRecord
  KINDS = %w[branch_prefix merge_summary quoted_context].freeze
  MODES = %w[messages_only summary_only messages_plus_summary].freeze

  belongs_to :target_conversation, class_name: "Conversation"
  belongs_to :source_conversation, class_name: "Conversation"
  belongs_to :source_message, class_name: "ConversationMessage", optional: true
  belongs_to :summary_message, class_name: "ConversationMessage", optional: true

  validates :kind, presence: true, inclusion: { in: KINDS }
  validates :mode, presence: true, inclusion: { in: MODES }
  validates :position, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
end
```

### `app/models/conversation_summary_segment.rb`

```ruby
class ConversationSummarySegment < ApplicationRecord
  KINDS = %w[auto_compaction manual_summary merge_summary].freeze
  STATUSES = %w[active superseded].freeze

  belongs_to :conversation
  belongs_to :summary_message, class_name: "ConversationMessage"
  belongs_to :replaces_segment, class_name: "ConversationSummarySegment", optional: true

  validates :kind, presence: true, inclusion: { in: KINDS }
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :start_turn_sequence, :end_turn_sequence, presence: true
end
```

### `app/models/turn_workflow.rb`

```ruby
class TurnWorkflow < ApplicationRecord
  include HasPublicId

  STATUSES = %w[draft running awaiting_approval finished failed rejected stopped].freeze
  PLANNER_MODES = %w[serial_loop].freeze

  belongs_to :conversation_turn
  belongs_to :terminal_node, class_name: "WorkflowNode", optional: true

  has_many :nodes, class_name: "WorkflowNode", dependent: :destroy
  has_many :edges, class_name: "WorkflowEdge", dependent: :destroy

  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :planner_mode, presence: true, inclusion: { in: PLANNER_MODES }
  validates :conversation_turn_id, uniqueness: true
end
```

### `app/models/workflow_node.rb`

```ruby
class WorkflowNode < ApplicationRecord
  include HasPublicId

  NODE_TYPES = %w[model_step tool_call command_exec subagent_run join approval_gate finalize summary].freeze
  STATES = %w[ready blocked running awaiting_approval finished failed rejected skipped canceled timed_out].freeze

  belongs_to :turn_workflow

  has_many :incoming_edges, class_name: "WorkflowEdge", foreign_key: :to_node_id, dependent: :destroy, inverse_of: :to_node
  has_many :outgoing_edges, class_name: "WorkflowEdge", foreign_key: :from_node_id, dependent: :destroy, inverse_of: :from_node
  has_many :events, class_name: "WorkflowNodeEvent", dependent: :destroy
  has_many :artifacts, class_name: "WorkflowArtifact", dependent: :destroy
  has_many :subagent_runs, dependent: :destroy
  has_many :process_runs, dependent: :destroy
  has_many :approval_requests, dependent: :destroy

  validates :ordinal, presence: true, uniqueness: { scope: :turn_workflow_id }
  validates :node_type, presence: true, inclusion: { in: NODE_TYPES }
  validates :state, presence: true, inclusion: { in: STATES }
  validates :attempt, numericality: { only_integer: true, greater_than: 0 }
end
```

### `app/models/workflow_edge.rb`

```ruby
class WorkflowEdge < ApplicationRecord
  belongs_to :turn_workflow
  belongs_to :from_node, class_name: "WorkflowNode"
  belongs_to :to_node, class_name: "WorkflowNode"

  validates :from_node_id, uniqueness: { scope: :to_node_id }
  validate :nodes_must_belong_to_turn_workflow
  validate :ordinal_must_increase

  private

  def nodes_must_belong_to_turn_workflow
    return if from_node.blank? || to_node.blank? || turn_workflow.blank?
    return if from_node.turn_workflow_id == turn_workflow_id && to_node.turn_workflow_id == turn_workflow_id

    errors.add(:turn_workflow, "must match both edge endpoints")
  end

  def ordinal_must_increase
    return if from_node.blank? || to_node.blank?
    return if from_node.turn_workflow_id == to_node.turn_workflow_id && from_node.ordinal < to_node.ordinal

    errors.add(:to_node, "must have a higher ordinal in the same workflow")
  end
end
```

### `app/models/workflow_node_event.rb`

```ruby
class WorkflowNodeEvent < ApplicationRecord
  KINDS = %w[status_changed activity output_delta approval_requested approval_resolved diagnostic resource_linked].freeze

  belongs_to :turn_workflow
  belongs_to :workflow_node

  validates :kind, presence: true, inclusion: { in: KINDS }
end
```

### `app/models/workflow_artifact.rb`

```ruby
class WorkflowArtifact < ApplicationRecord
  KINDS = %w[tool_result file_ref image_ref patch structured_result join_result assistant_output_candidate log_ref].freeze
  STORAGE_MODES = %w[inline_json active_storage foreign_reference external_url].freeze

  belongs_to :turn_workflow
  belongs_to :workflow_node

  has_one_attached :file

  validates :kind, presence: true, inclusion: { in: KINDS }
  validates :storage_mode, presence: true, inclusion: { in: STORAGE_MODES }
end
```

### `app/models/subagent_run.rb`

```ruby
class SubagentRun < ApplicationRecord
  include HasPublicId

  STATUSES = %w[starting running waiting succeeded failed killed timed_out lost closed].freeze
  MANAGEMENT_MODES = %w[managed read_only_external].freeze

  belongs_to :workflow_node
  belongs_to :turn_workflow
  belongs_to :conversation_turn
  belongs_to :conversation
  belongs_to :child_conversation, class_name: "Conversation", optional: true
  belongs_to :result_artifact, class_name: "WorkflowArtifact", optional: true

  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :management_mode, presence: true, inclusion: { in: MANAGEMENT_MODES }
end
```

### `app/models/process_run.rb`

```ruby
class ProcessRun < ApplicationRecord
  include HasPublicId

  KINDS = %w[turn_command background_service].freeze
  STATUSES = %w[starting running succeeded failed killed timed_out lost closed].freeze
  STARTED_BY_TYPES = %w[agent user].freeze

  belongs_to :workflow_node
  belongs_to :turn_workflow
  belongs_to :conversation_turn
  belongs_to :conversation
  belongs_to :log_artifact, class_name: "WorkflowArtifact", optional: true

  validates :kind, presence: true, inclusion: { in: KINDS }
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :started_by_type, presence: true, inclusion: { in: STARTED_BY_TYPES }
  validates :command, presence: true

  validate :kind_specific_constraints

  private

  def kind_specific_constraints
    if kind == "turn_command"
      errors.add(:timeout_s, "must be present for turn commands") if timeout_s.blank?
    end

    if kind == "background_service" && timeout_s.present?
      errors.add(:timeout_s, "must be blank for background services")
    end
  end
end
```

### `app/models/approval_request.rb`

```ruby
class ApprovalRequest < ApplicationRecord
  SCOPES = %w[tool_call command_exec subagent message_edit external_write].freeze
  STATUSES = %w[pending approved denied expired canceled].freeze

  belongs_to :workflow_node
  belongs_to :turn_workflow

  validates :scope, presence: true, inclusion: { in: SCOPES }
  validates :status, presence: true, inclusion: { in: STATUSES }
end
```

### `app/models/execution_lease.rb`

```ruby
class ExecutionLease < ApplicationRecord
  STATUSES = %w[active released expired].freeze

  validates :subject_type, :subject_id, :holder_type, :holder_id, :execution_request_key, :status, :lease_expires_at, :heartbeat_at, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :slots, numericality: { only_integer: true, greater_than: 0 }
  validates :execution_request_key, uniqueness: { scope: [:subject_type, :subject_id] }
end
```

### `app/models/conversation_draft.rb`

```ruby
class ConversationDraft < ApplicationRecord
  belongs_to :conversation
  belongs_to :selected_agent, class_name: "Agent", optional: true

  validates :conversation_id, uniqueness: true
end
```

### `app/models/tool_permission_grant.rb`

```ruby
class ToolPermissionGrant < ApplicationRecord
  STATUSES = %w[active revoked expired].freeze
  SCOPE_KINDS = %w[exact_call prefix_rule tool_family conversation_local workspace_local].freeze

  validates :subject_type, :subject_id, :tool_name, :scope_kind, :status, presence: true
  validates :scope_kind, inclusion: { in: SCOPE_KINDS }
  validates :status, inclusion: { in: STATUSES }
end
```

### `app/models/workspace_document.rb`

```ruby
class WorkspaceDocument < ApplicationRecord
  SCOPES = %w[conversation_local tree_shared agent_local global].freeze
  STATUSES = %w[active archived].freeze

  belongs_to :conversation, optional: true
  belongs_to :latest_revision, class_name: "WorkspaceDocumentRevision", optional: true

  has_many :revisions, class_name: "WorkspaceDocumentRevision", dependent: :destroy

  validates :conversation_scope, presence: true, inclusion: { in: SCOPES }
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :path, presence: true
end
```

### `app/models/workspace_document_revision.rb`

```ruby
class WorkspaceDocumentRevision < ApplicationRecord
  SOURCE_KINDS = %w[manual memory_tool subagent_result system].freeze

  belongs_to :workspace_document
  belongs_to :workflow_artifact, optional: true

  validates :body_markdown, presence: true
  validates :source_kind, presence: true, inclusion: { in: SOURCE_KINDS }
end
```

### `app/models/tool_call_fact.rb`

```ruby
class ToolCallFact < ApplicationRecord
  EXECUTION_SCOPES = %w[parent subagent].freeze

  belongs_to :conversation
  belongs_to :conversation_turn
  belongs_to :turn_workflow
  belongs_to :workflow_node

  validates :tool_name, :execution_scope, :result_status, presence: true
  validates :execution_scope, inclusion: { in: EXECUTION_SCOPES }
  validates :model_attempts, :tool_executions, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
end
```

## Backend Test Inventory

Write these first. This is the complete v1 backend inventory I would want before starting the deferred UI/runtime follow-up work.

### Model Tests

- `test/models/agent_test.rb`
- `test/models/conversation_test.rb`
- `test/models/conversation_closure_test.rb`
- `test/models/conversation_turn_test.rb`
- `test/models/conversation_message_test.rb`
- `test/models/conversation_message_visibility_test.rb`
- `test/models/message_attachment_test.rb`
- `test/models/conversation_import_test.rb`
- `test/models/conversation_summary_segment_test.rb`
- `test/models/turn_workflow_test.rb`
- `test/models/workflow_node_test.rb`
- `test/models/workflow_edge_test.rb`
- `test/models/workflow_node_event_test.rb`
- `test/models/workflow_artifact_test.rb`
- `test/models/subagent_run_test.rb`
- `test/models/process_run_test.rb`
- `test/models/approval_request_test.rb`
- `test/models/execution_lease_test.rb`
- `test/models/conversation_draft_test.rb`
- `test/models/tool_permission_grant_test.rb`
- `test/models/workspace_document_test.rb`
- `test/models/workspace_document_revision_test.rb`
- `test/models/tool_call_fact_test.rb`

### Service Tests

- `test/services/conversations/create_root_test.rb`
- `test/services/conversations/create_branch_test.rb`
- `test/services/turns/start_user_turn_test.rb`
- `test/services/turns/queue_follow_up_test.rb`
- `test/services/turns/steer_current_input_test.rb`
- `test/services/workflows/mutator_test.rb`
- `test/services/workflows/scheduler_test.rb`
- `test/services/workflows/join_reducer_test.rb`
- `test/services/workflows/failure_propagator_test.rb`
- `test/services/subagents/spawn_test.rb`
- `test/services/processes/start_test.rb`
- `test/services/approvals/resolve_test.rb`
- `test/services/leases/acquire_test.rb`
- `test/services/attachments/materialize_refs_test.rb`
- `test/services/statistics/project_tool_call_facts_test.rb`

## Representative Tests

### `test/models/conversation_test.rb`

```ruby
require "test_helper"

class ConversationTest < ActiveSupport::TestCase
  test "root conversation may point root_conversation_id to itself after creation" do
    agent = build_agent
    conversation = build_root_conversation(agent: agent)

    assert_equal conversation.id, conversation.root_conversation_id
    assert conversation.root?
  end

  test "managed_read_only? reflects managed subagent ownership" do
    agent = build_agent
    conversation = build_root_conversation(agent: agent)

    refute conversation.managed_read_only?

    conversation.update_column(:managed_by_subagent_run_id, 123)
    assert conversation.reload.managed_read_only?
  end

  test "requires status from allowed set" do
    agent = build_agent
    conversation = Conversation.new(agent: agent, title: "Bad", status: "wat", metadata: {})

    refute conversation.valid?
    assert_includes conversation.errors[:status], "is not included in the list"
  end
end
```

### `test/models/conversation_turn_test.rb`

```ruby
require "test_helper"

class ConversationTurnTest < ActiveSupport::TestCase
  test "sequence is unique per conversation" do
    agent = build_agent
    conversation = build_root_conversation(agent: agent)

    build_turn(conversation: conversation, attributes: { sequence: 1 })
    duplicate = ConversationTurn.new(conversation: conversation, sequence: 1, trigger_kind: "user", status: "draft", metadata: {})

    refute duplicate.valid?
    assert_includes duplicate.errors[:sequence], "has already been taken"
  end

  test "queued scope returns queued turns in queue order" do
    agent = build_agent
    conversation = build_root_conversation(agent: agent)

    later = build_turn(conversation: conversation, attributes: { status: "queued", queue_position: 2 })
    earlier = build_turn(conversation: conversation, attributes: { status: "queued", queue_position: 1 })

    assert_equal [earlier.id, later.id], conversation.turns.queued.pluck(:id)
  end
end
```

### `test/models/workflow_edge_test.rb`

```ruby
require "test_helper"

class WorkflowEdgeTest < ActiveSupport::TestCase
  test "requires to_node ordinal to be greater than from_node ordinal" do
    agent = build_agent
    conversation = build_root_conversation(agent: agent)
    turn = build_turn(conversation: conversation)
    workflow = TurnWorkflow.create!(conversation_turn: turn, status: "draft", planner_mode: "serial_loop", metadata: {})
    first = WorkflowNode.create!(turn_workflow: workflow, ordinal: 1, node_type: "model_step", state: "ready", metadata: {})
    second = WorkflowNode.create!(turn_workflow: workflow, ordinal: 2, node_type: "finalize", state: "blocked", metadata: {})

    valid_edge = WorkflowEdge.new(turn_workflow: workflow, from_node: first, to_node: second, metadata: {})
    invalid_edge = WorkflowEdge.new(turn_workflow: workflow, from_node: second, to_node: first, metadata: {})

    assert valid_edge.valid?
    refute invalid_edge.valid?
    assert_includes invalid_edge.errors[:to_node], "must have a higher ordinal in the same workflow"
  end
end
```

### `test/models/process_run_test.rb`

```ruby
require "test_helper"

class ProcessRunTest < ActiveSupport::TestCase
  test "turn_command requires timeout" do
    agent = build_agent
    conversation = build_root_conversation(agent: agent)
    turn = build_turn(conversation: conversation)
    workflow = TurnWorkflow.create!(conversation_turn: turn, status: "running", planner_mode: "serial_loop", metadata: {})
    node = WorkflowNode.create!(turn_workflow: workflow, ordinal: 1, node_type: "command_exec", state: "ready", metadata: {})

    run = ProcessRun.new(
      workflow_node: node,
      turn_workflow: workflow,
      conversation_turn: turn,
      conversation: conversation,
      kind: "turn_command",
      status: "starting",
      started_by_type: "agent",
      command: "bin/test",
      env_preview: {},
      port_hints: [],
      metadata: {}
    )

    refute run.valid?
    assert_includes run.errors[:timeout_s], "must be present for turn commands"
  end

  test "background_service forbids timeout" do
    agent = build_agent
    conversation = build_root_conversation(agent: agent)
    turn = build_turn(conversation: conversation)
    workflow = TurnWorkflow.create!(conversation_turn: turn, status: "running", planner_mode: "serial_loop", metadata: {})
    node = WorkflowNode.create!(turn_workflow: workflow, ordinal: 1, node_type: "command_exec", state: "ready", metadata: {})

    run = ProcessRun.new(
      workflow_node: node,
      turn_workflow: workflow,
      conversation_turn: turn,
      conversation: conversation,
      kind: "background_service",
      status: "starting",
      started_by_type: "user",
      command: "bin/server",
      timeout_s: 30,
      env_preview: {},
      port_hints: [],
      metadata: {}
    )

    refute run.valid?
    assert_includes run.errors[:timeout_s], "must be blank for background services"
  end
end
```

### `test/models/message_attachment_test.rb`

```ruby
require "test_helper"

class MessageAttachmentTest < ActiveSupport::TestCase
  test "requires an attached file" do
    agent = build_agent
    conversation = build_root_conversation(agent: agent)
    turn = build_turn(conversation: conversation)
    message = build_message(conversation: conversation, turn: turn)

    attachment = MessageAttachment.new(
      conversation: conversation,
      conversation_message: message,
      position: 1,
      kind: "file",
      preparation_status: "pending",
      preparation_ref: {},
      metadata: {}
    )

    refute attachment.valid?
    assert_includes attachment.errors[:file], "must be attached"
  end
end
```

### `test/models/execution_lease_test.rb`

```ruby
require "test_helper"

class ExecutionLeaseTest < ActiveSupport::TestCase
  test "execution_request_key is unique within subject" do
    ExecutionLease.create!(
      subject_type: "workflow_node",
      subject_id: 1,
      holder_type: "worker",
      holder_id: 1,
      execution_request_key: "abc",
      status: "active",
      slots: 1,
      lease_expires_at: 5.minutes.from_now,
      heartbeat_at: Time.current,
      recovery_metadata: {}
    )

    duplicate = ExecutionLease.new(
      subject_type: "workflow_node",
      subject_id: 1,
      holder_type: "worker",
      holder_id: 2,
      execution_request_key: "abc",
      status: "active",
      slots: 1,
      lease_expires_at: 5.minutes.from_now,
      heartbeat_at: Time.current,
      recovery_metadata: {}
    )

    refute duplicate.valid?
    assert_includes duplicate.errors[:execution_request_key], "has already been taken"
  end
end
```

## Representative Service Code

### `app/services/conversations/create_root.rb`

```ruby
module Conversations
  class CreateRoot
    def self.call(agent:, title:, metadata: {})
      new(agent:, title:, metadata:).call
    end

    def initialize(agent:, title:, metadata: {})
      @agent = agent
      @title = title
      @metadata = metadata
    end

    def call
      Conversation.transaction do
        conversation = Conversation.create!(
          agent: agent,
          title: title,
          status: "active",
          depth: 0,
          branch_position: 0,
          children_count: 0,
          metadata: metadata
        )

        conversation.update!(root_conversation: conversation)

        ConversationClosure.create!(
          ancestor_conversation: conversation,
          descendant_conversation: conversation,
          depth: 0
        )

        ConversationDraft.create!(
          conversation: conversation,
          attachment_refs: [],
          metadata: {}
        )

        conversation
      end
    end

    private

    attr_reader :agent, :title, :metadata
  end
end
```

### `test/services/conversations/create_root_test.rb`

```ruby
require "test_helper"

class Conversations::CreateRootTest < ActiveSupport::TestCase
  test "creates a root conversation with a self closure row and draft" do
    agent = build_agent

    conversation = Conversations::CreateRoot.call(agent: agent, title: "Root conversation")

    assert_equal conversation.id, conversation.root_conversation_id
    assert_nil conversation.parent_conversation_id
    assert_equal "active", conversation.status

    closure = ConversationClosure.find_by!(
      ancestor_conversation_id: conversation.id,
      descendant_conversation_id: conversation.id
    )
    assert_equal 0, closure.depth

    assert_equal conversation.id, conversation.draft.conversation_id
  end
end
```

## First Service Tests To Make Green

After model tests pass, implement only these first:

1. `Conversations::CreateRoot`
2. `Conversations::CreateBranch`
3. `Turns::StartUserTurn`
4. `Turns::QueueFollowUp`
5. `Turns::SteerCurrentInput`
6. `Workflows::Mutator`
7. `Processes::Start`
8. `Subagents::Spawn`

Do not implement the whole runtime at once. These services establish the core invariants.

## Self-Review

This blueprint is intentionally implementation-first.

- It avoids schema choices that fight Rails conventions.
- It keeps self-referential inserts realistic by leaving `root_conversation_id` nullable in the database.
- It uses `has_one_attached` instead of hand-managed Active Storage foreign keys.
- It keeps model logic local and pushes orchestration into services.
- It includes database constraints for uniqueness and referential integrity where Rails alone would be too weak.
- It defines the first backend test inventory before any deferred UI/runtime work.

The main remaining deliberate omissions are:

- no controller/channel code
- no UI/presenter code
- no background job orchestration details
- no provider/runtime adapter implementation yet

Those omissions are intentional and belong in [CoreMatrix Agent UI And Runtime Follow-Up](./2026-03-23-core-matrix-agent-ui-runtime-follow-up.md).
