module Conversations
  class BlockerSnapshotQuery
    def self.call(...)
      new(...).call
    end

    def initialize(conversation:, turns: conversation.turns, owned_subagent_connection_ids: nil, owned_subagent_conversation_ids: nil)
      @conversation = conversation
      @turns = turns
      @explicit_owned_subagent_connection_ids = owned_subagent_connection_ids
      @explicit_owned_subagent_conversation_ids = owned_subagent_conversation_ids
    end

    def call
      turn_counts = aggregate_turn_counts
      workflow_counts = aggregate_workflow_counts
      agent_task_counts = aggregate_agent_task_counts
      interaction_counts = aggregate_interaction_counts
      process_counts = aggregate_process_counts
      subagent_counts = aggregate_subagent_counts
      execution_lease_counts = aggregate_execution_lease_counts
      dependency_flags = aggregate_dependency_flags

      ConversationBlockerSnapshot.new(
        retained: @conversation.retained?,
        active: @conversation.active?,
        closing: @conversation.closing?,
        queued_turn_count: turn_counts.fetch(:queued_turn_count),
        active_turn_count: turn_counts.fetch(:active_turn_count),
        active_workflow_count: workflow_counts.fetch(:active_workflow_count),
        queued_agent_task_count: agent_task_counts.fetch(:queued_agent_task_count),
        active_agent_task_count: agent_task_counts.fetch(:active_agent_task_count),
        open_interaction_count: interaction_counts.fetch(:open_interaction_count),
        open_blocking_interaction_count: interaction_counts.fetch(:open_blocking_interaction_count),
        running_process_count: process_counts.fetch(:running_process_count),
        running_background_process_count: process_counts.fetch(:running_background_process_count),
        detached_tool_process_count: 0,
        running_subagent_count: subagent_counts.fetch(:running_subagent_count),
        close_pending_or_open_subagent_count: subagent_counts.fetch(:close_pending_or_open_subagent_count),
        active_execution_lease_count: execution_lease_counts.fetch(:active_execution_lease_count),
        degraded_close_count: process_counts.fetch(:process_close_failures) +
          subagent_counts.fetch(:subagent_close_failures) +
          agent_task_counts.fetch(:task_close_failures),
        descendant_lineage_blockers: descendant_lineage_blockers,
        root_lineage_store_blocker: dependency_flags.fetch(:root_lineage_store_blocker),
        variable_provenance_blocker: dependency_flags.fetch(:variable_provenance_blocker),
        import_provenance_blocker: dependency_flags.fetch(:import_provenance_blocker)
      )
    end

    private

    def turn_scope
      @turn_scope ||= @turns.where(conversation_id: @conversation.id)
    end

    def workflow_run_scope
      @workflow_run_scope ||= WorkflowRun.where(conversation_id: @conversation.id, turn_id: turn_scope.select(:id))
    end

    def agent_task_scope
      @agent_task_scope ||= AgentTaskRun.where(conversation_id: @conversation.id, turn_id: turn_scope.select(:id))
    end

    def interaction_scope
      @interaction_scope ||= HumanInteractionRequest.where(conversation_id: @conversation.id, turn_id: turn_scope.select(:id))
    end

    def process_scope
      @process_scope ||= ProcessRun.where(conversation_id: @conversation.id, turn_id: turn_scope.select(:id))
    end

    def execution_lease_scope
      @execution_lease_scope ||= ExecutionLease
        .joins(:workflow_run)
        .where(workflow_runs: { conversation_id: @conversation.id, turn_id: turn_scope.select(:id) })
    end

    def descendant_lineage_blockers
      scope = @conversation.descendant_closures.where.not(descendant_conversation_id: @conversation.id)
      scope = scope.where.not(descendant_conversation_id: owned_subagent_conversation_ids) if owned_subagent_conversation_ids.any?
      scope.count
    end

    def aggregate_turn_counts
      @aggregate_turn_counts ||= aggregate_counts(
        turn_scope,
        queued_turn_count: "SUM(CASE WHEN lifecycle_state = 'queued' THEN 1 ELSE 0 END)",
        active_turn_count: "SUM(CASE WHEN lifecycle_state = 'active' THEN 1 ELSE 0 END)"
      )
    end

    def aggregate_workflow_counts
      @aggregate_workflow_counts ||= aggregate_counts(
        workflow_run_scope,
        active_workflow_count: "SUM(CASE WHEN lifecycle_state = 'active' THEN 1 ELSE 0 END)"
      )
    end

    def aggregate_agent_task_counts
      @aggregate_agent_task_counts ||= aggregate_counts(
        agent_task_scope,
        queued_agent_task_count: "SUM(CASE WHEN lifecycle_state = 'queued' THEN 1 ELSE 0 END)",
        active_agent_task_count: "SUM(CASE WHEN lifecycle_state = 'running' THEN 1 ELSE 0 END)",
        task_close_failures: "SUM(CASE WHEN close_state = 'failed' THEN 1 ELSE 0 END)"
      )
    end

    def aggregate_interaction_counts
      @aggregate_interaction_counts ||= aggregate_counts(
        interaction_scope,
        open_interaction_count: "SUM(CASE WHEN lifecycle_state = 'open' THEN 1 ELSE 0 END)",
        open_blocking_interaction_count: "SUM(CASE WHEN lifecycle_state = 'open' AND blocking IS TRUE THEN 1 ELSE 0 END)"
      )
    end

    def aggregate_process_counts
      @aggregate_process_counts ||= aggregate_counts(
        process_scope,
        running_process_count: "SUM(CASE WHEN lifecycle_state = 'running' THEN 1 ELSE 0 END)",
        running_background_process_count: "SUM(CASE WHEN lifecycle_state = 'running' AND kind = 'background_service' THEN 1 ELSE 0 END)",
        process_close_failures: "SUM(CASE WHEN close_state IN ('failed', 'closed') AND close_outcome_kind IN ('residual_abandoned', 'timed_out_forced') THEN 1 ELSE 0 END)"
      )
    end

    def aggregate_subagent_counts
      @aggregate_subagent_counts ||= aggregate_counts(
        owned_subagent_scope,
        running_subagent_count: "SUM(CASE WHEN close_state IN ('open', 'requested', 'acknowledged') AND observed_status = 'running' THEN 1 ELSE 0 END)",
        close_pending_or_open_subagent_count: "SUM(CASE WHEN close_state IN ('open', 'requested', 'acknowledged') THEN 1 ELSE 0 END)",
        subagent_close_failures: "SUM(CASE WHEN close_state = 'failed' THEN 1 ELSE 0 END)"
      )
    end

    def aggregate_execution_lease_counts
      @aggregate_execution_lease_counts ||= aggregate_counts(
        execution_lease_scope,
        active_execution_lease_count: "SUM(CASE WHEN released_at IS NULL THEN 1 ELSE 0 END)"
      )
    end

    def aggregate_dependency_flags
      @aggregate_dependency_flags ||= begin
        values = Conversation.where(id: @conversation.id).pick(
          Arel.sql("EXISTS (SELECT 1 FROM lineage_stores WHERE root_conversation_id = conversations.id)"),
          Arel.sql("EXISTS (SELECT 1 FROM canonical_variables WHERE source_conversation_id = conversations.id)"),
          Arel.sql("EXISTS (SELECT 1 FROM conversation_imports WHERE source_conversation_id = conversations.id)")
        )
        root_lineage_store_blocker, variable_provenance_blocker, import_provenance_blocker =
          values.is_a?(Array) ? values : [values]

        {
          root_lineage_store_blocker: ActiveRecord::Type::Boolean.new.cast(root_lineage_store_blocker),
          variable_provenance_blocker: ActiveRecord::Type::Boolean.new.cast(variable_provenance_blocker),
          import_provenance_blocker: ActiveRecord::Type::Boolean.new.cast(import_provenance_blocker),
        }
      end
    end

    def owned_subagent_connection_ids
      @owned_subagent_connection_ids ||= @explicit_owned_subagent_connection_ids || owned_subagent_tree.connection_ids
    end

    def owned_subagent_conversation_ids
      @owned_subagent_conversation_ids ||= @explicit_owned_subagent_conversation_ids || owned_subagent_tree.conversation_ids
    end

    def owned_subagent_tree
      @owned_subagent_tree ||= SubagentConnections::OwnedTree.new(owner_conversation: @conversation)
    end

    def owned_subagent_scope
      @owned_subagent_scope ||= SubagentConnection.where(id: owned_subagent_connection_ids)
    end

    def aggregate_counts(scope, aggregates)
      values = relation_for_aggregate(scope).pick(*aggregates.values.map { |expression| Arel.sql(expression) })
      normalized_values = values.is_a?(Array) ? values : [values]
      normalized_values.map! { |value| value.to_i }
      aggregates.keys.zip(normalized_values).to_h
    end

    def relation_for_aggregate(scope)
      scope.except(:select, :order, :includes, :preload, :eager_load)
    end
  end
end
