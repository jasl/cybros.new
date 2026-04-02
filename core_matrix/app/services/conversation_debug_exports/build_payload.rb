module ConversationDebugExports
  class BuildPayload
    BUNDLE_KIND = "conversation_debug_export".freeze
    BUNDLE_VERSION = "2026-04-02".freeze

    def self.call(...)
      new(...).call
    end

    def initialize(conversation:)
      @conversation = conversation
    end

    def call
      ConversationDiagnostics::RecomputeConversationSnapshot.call(conversation: @conversation)
      turn_snapshots = TurnDiagnosticsSnapshot.where(conversation: @conversation).joins(:turn).includes(:turn).order("turns.sequence ASC")

      {
        "bundle_kind" => BUNDLE_KIND,
        "bundle_version" => BUNDLE_VERSION,
        "conversation_payload" => ConversationExports::BuildConversationPayload.call(conversation: @conversation),
        "diagnostics" => {
          "conversation" => serialize_conversation_snapshot(
            ConversationDiagnosticsSnapshot.find_by(conversation: @conversation)
          ),
          "turns" => turn_snapshots.map { |snapshot| serialize_turn_snapshot(snapshot) },
        },
        "workflow_runs" => workflow_runs.map { |workflow_run| serialize_workflow_run(workflow_run) },
        "workflow_nodes" => workflow_nodes.map { |workflow_node| serialize_workflow_node(workflow_node) },
        "workflow_node_events" => workflow_node_events.map { |event| serialize_workflow_node_event(event) },
        "agent_task_runs" => agent_task_runs.map { |task_run| serialize_agent_task_run(task_run) },
        "tool_invocations" => tool_invocations.map { |tool_invocation| serialize_tool_invocation(tool_invocation) },
        "command_runs" => command_runs.map { |command_run| serialize_command_run(command_run) },
        "process_runs" => process_runs.map { |process_run| serialize_process_run(process_run) },
        "subagent_sessions" => subagent_sessions.map { |session| serialize_subagent_session(session) },
        "usage_events" => usage_events.map { |event| serialize_usage_event(event) },
      }
    end

    private

    def workflow_runs
      @workflow_runs ||= @conversation.workflow_runs.order(:created_at, :id)
    end

    def workflow_nodes
      @workflow_nodes ||= WorkflowNode.where(workflow_run: workflow_runs).order(:created_at, :id)
    end

    def workflow_node_events
      @workflow_node_events ||= WorkflowNodeEvent.where(workflow_run: workflow_runs).order(:created_at, :id)
    end

    def agent_task_runs
      @agent_task_runs ||= AgentTaskRun.where(conversation: @conversation).includes(:workflow_run, :workflow_node, :subagent_session).order(:created_at, :id)
    end

    def tool_invocations
      @tool_invocations ||= ToolInvocation
        .includes(:tool_definition, :tool_implementation, :tool_binding, :workflow_node, :agent_task_run)
        .where(workflow_node: workflow_nodes)
        .or(
          ToolInvocation
            .includes(:tool_definition, :tool_implementation, :tool_binding, :workflow_node, :agent_task_run)
            .where(agent_task_run: agent_task_runs)
        )
        .order(:created_at, :id)
    end

    def command_runs
      @command_runs ||= CommandRun
        .includes(:tool_invocation, :workflow_node, :agent_task_run)
        .where(workflow_node: workflow_nodes)
        .or(
          CommandRun
            .includes(:tool_invocation, :workflow_node, :agent_task_run)
            .where(agent_task_run: agent_task_runs)
        )
        .order(:created_at, :id)
    end

    def process_runs
      @process_runs ||= ProcessRun.where(conversation: @conversation).includes(:workflow_node, :origin_message).order(:created_at, :id)
    end

    def subagent_sessions
      @subagent_sessions ||= SubagentSession
        .where(owner_conversation: @conversation)
        .or(SubagentSession.where(conversation: @conversation))
        .order(:created_at, :id)
    end

    def usage_events
      @usage_events ||= UsageEvent.where(conversation_id: @conversation.id).order(:occurred_at, :id)
    end

    def turn_public_id_map
      @turn_public_id_map ||= Turn.where(id: usage_events.map(&:turn_id).compact.uniq).pluck(:id, :public_id).to_h
    end

    def user_public_id_map
      @user_public_id_map ||= User.where(id: usage_events.map(&:user_id).compact.uniq).pluck(:id, :public_id).to_h
    end

    def workspace_public_id_map
      @workspace_public_id_map ||= Workspace.where(id: usage_events.map(&:workspace_id).compact.uniq).pluck(:id, :public_id).to_h
    end

    def agent_deployment_public_id_map
      @agent_deployment_public_id_map ||= AgentDeployment.where(id: usage_events.map(&:agent_deployment_id).compact.uniq).pluck(:id, :public_id).to_h
    end

    def serialize_conversation_snapshot(snapshot)
      return {} if snapshot.blank?

      {
        "conversation_id" => snapshot.conversation.public_id,
        "lifecycle_state" => snapshot.lifecycle_state,
        "turn_count" => snapshot.turn_count,
        "active_turn_count" => snapshot.active_turn_count,
        "completed_turn_count" => snapshot.completed_turn_count,
        "failed_turn_count" => snapshot.failed_turn_count,
        "canceled_turn_count" => snapshot.canceled_turn_count,
        "usage_event_count" => snapshot.usage_event_count,
        "input_tokens_total" => snapshot.input_tokens_total,
        "output_tokens_total" => snapshot.output_tokens_total,
        "estimated_cost_total" => snapshot.estimated_cost_total.to_s("F"),
        "provider_round_count" => snapshot.provider_round_count,
        "tool_call_count" => snapshot.tool_call_count,
        "tool_failure_count" => snapshot.tool_failure_count,
        "command_run_count" => snapshot.command_run_count,
        "command_failure_count" => snapshot.command_failure_count,
        "process_run_count" => snapshot.process_run_count,
        "process_failure_count" => snapshot.process_failure_count,
        "subagent_session_count" => snapshot.subagent_session_count,
        "resume_attempt_count" => snapshot.resume_attempt_count,
        "retry_attempt_count" => snapshot.retry_attempt_count,
        "most_expensive_turn_id" => snapshot.most_expensive_turn&.public_id,
        "most_rounds_turn_id" => snapshot.most_rounds_turn&.public_id,
        "metadata" => snapshot.metadata,
      }.compact
    end

    def serialize_turn_snapshot(snapshot)
      {
        "conversation_id" => snapshot.conversation.public_id,
        "turn_id" => snapshot.turn.public_id,
        "lifecycle_state" => snapshot.lifecycle_state,
        "usage_event_count" => snapshot.usage_event_count,
        "input_tokens_total" => snapshot.input_tokens_total,
        "output_tokens_total" => snapshot.output_tokens_total,
        "estimated_cost_total" => snapshot.estimated_cost_total.to_s("F"),
        "provider_round_count" => snapshot.provider_round_count,
        "tool_call_count" => snapshot.tool_call_count,
        "tool_failure_count" => snapshot.tool_failure_count,
        "command_run_count" => snapshot.command_run_count,
        "command_failure_count" => snapshot.command_failure_count,
        "process_run_count" => snapshot.process_run_count,
        "process_failure_count" => snapshot.process_failure_count,
        "subagent_session_count" => snapshot.subagent_session_count,
        "resume_attempt_count" => snapshot.resume_attempt_count,
        "retry_attempt_count" => snapshot.retry_attempt_count,
        "metadata" => snapshot.metadata,
      }
    end

    def serialize_workflow_run(workflow_run)
      {
        "workflow_run_id" => workflow_run.public_id,
        "conversation_id" => workflow_run.conversation.public_id,
        "turn_id" => workflow_run.turn.public_id,
        "lifecycle_state" => workflow_run.lifecycle_state,
        "wait_state" => workflow_run.wait_state,
        "wait_reason_kind" => workflow_run.wait_reason_kind,
        "wait_reason_payload" => workflow_run.wait_reason_payload,
        "blocking_resource_type" => workflow_run.blocking_resource_type,
        "blocking_resource_id" => workflow_run.blocking_resource_id,
        "resume_policy" => workflow_run.resume_policy,
        "resume_metadata" => workflow_run.resume_metadata,
        "waiting_since_at" => workflow_run.waiting_since_at&.iso8601(6),
        "cancellation_requested_at" => workflow_run.cancellation_requested_at&.iso8601(6),
        "created_at" => workflow_run.created_at&.iso8601(6),
        "updated_at" => workflow_run.updated_at&.iso8601(6),
      }.compact
    end

    def serialize_workflow_node(workflow_node)
      {
        "workflow_node_id" => workflow_node.public_id,
        "workflow_run_id" => workflow_node.workflow_run.public_id,
        "conversation_id" => workflow_node.conversation.public_id,
        "turn_id" => workflow_node.turn.public_id,
        "yielding_workflow_node_id" => workflow_node.yielding_workflow_node&.public_id,
        "node_key" => workflow_node.node_key,
        "node_type" => workflow_node.node_type,
        "ordinal" => workflow_node.ordinal,
        "stage_index" => workflow_node.stage_index,
        "stage_position" => workflow_node.stage_position,
        "lifecycle_state" => workflow_node.lifecycle_state,
        "presentation_policy" => workflow_node.presentation_policy,
        "decision_source" => workflow_node.decision_source,
        "metadata" => workflow_node.metadata,
        "started_at" => workflow_node.started_at&.iso8601(6),
        "finished_at" => workflow_node.finished_at&.iso8601(6),
        "created_at" => workflow_node.created_at&.iso8601(6),
        "updated_at" => workflow_node.updated_at&.iso8601(6),
      }.compact
    end

    def serialize_workflow_node_event(event)
      {
        "workflow_node_id" => event.workflow_node.public_id,
        "workflow_run_id" => event.workflow_run.public_id,
        "conversation_id" => event.conversation&.public_id,
        "turn_id" => event.turn&.public_id,
        "workflow_node_key" => event.workflow_node_key,
        "workflow_node_ordinal" => event.workflow_node_ordinal,
        "event_kind" => event.event_kind,
        "ordinal" => event.ordinal,
        "presentation_policy" => event.presentation_policy,
        "payload" => event.payload,
        "created_at" => event.created_at&.iso8601(6),
        "updated_at" => event.updated_at&.iso8601(6),
      }.compact
    end

    def serialize_agent_task_run(task_run)
      {
        "agent_task_run_id" => task_run.public_id,
        "workflow_run_id" => task_run.workflow_run.public_id,
        "workflow_node_id" => task_run.workflow_node.public_id,
        "conversation_id" => task_run.conversation.public_id,
        "turn_id" => task_run.turn.public_id,
        "subagent_session_id" => task_run.subagent_session&.public_id,
        "origin_turn_id" => task_run.origin_turn&.public_id,
        "holder_agent_deployment_id" => task_run.holder_agent_deployment&.public_id,
        "kind" => task_run.kind,
        "lifecycle_state" => task_run.lifecycle_state,
        "logical_work_id" => task_run.logical_work_id,
        "attempt_no" => task_run.attempt_no,
        "task_payload" => task_run.task_payload,
        "progress_payload" => task_run.progress_payload,
        "terminal_payload" => task_run.terminal_payload,
        "started_at" => task_run.started_at&.iso8601(6),
        "finished_at" => task_run.finished_at&.iso8601(6),
        "created_at" => task_run.created_at&.iso8601(6),
        "updated_at" => task_run.updated_at&.iso8601(6),
      }.compact
    end

    def serialize_tool_invocation(tool_invocation)
      {
        "tool_invocation_id" => tool_invocation.public_id,
        "workflow_node_id" => tool_invocation.workflow_node&.public_id,
        "agent_task_run_id" => tool_invocation.agent_task_run&.public_id,
        "tool_binding_id" => tool_invocation.tool_binding.public_id,
        "tool_definition_id" => tool_invocation.tool_definition.public_id,
        "tool_implementation_id" => tool_invocation.tool_implementation.public_id,
        "tool_name" => tool_invocation.tool_definition.tool_name,
        "status" => tool_invocation.status,
        "attempt_no" => tool_invocation.attempt_no,
        "request_payload" => tool_invocation.request_payload,
        "response_payload" => tool_invocation.response_payload,
        "error_payload" => tool_invocation.error_payload,
        "metadata" => tool_invocation.metadata,
        "started_at" => tool_invocation.started_at&.iso8601(6),
        "finished_at" => tool_invocation.finished_at&.iso8601(6),
        "created_at" => tool_invocation.created_at&.iso8601(6),
        "updated_at" => tool_invocation.updated_at&.iso8601(6),
      }.compact
    end

    def serialize_command_run(command_run)
      {
        "command_run_id" => command_run.public_id,
        "workflow_node_id" => command_run.workflow_node&.public_id,
        "agent_task_run_id" => command_run.agent_task_run&.public_id,
        "tool_invocation_id" => command_run.tool_invocation.public_id,
        "lifecycle_state" => command_run.lifecycle_state,
        "command_line" => command_run.command_line,
        "timeout_seconds" => command_run.timeout_seconds,
        "metadata" => command_run.metadata,
        "started_at" => command_run.started_at&.iso8601(6),
        "ended_at" => command_run.ended_at&.iso8601(6),
        "created_at" => command_run.created_at&.iso8601(6),
        "updated_at" => command_run.updated_at&.iso8601(6),
      }.compact
    end

    def serialize_process_run(process_run)
      {
        "process_run_id" => process_run.public_id,
        "workflow_node_id" => process_run.workflow_node.public_id,
        "workflow_run_id" => process_run.workflow_run&.public_id,
        "conversation_id" => process_run.conversation.public_id,
        "turn_id" => process_run.turn.public_id,
        "origin_message_id" => process_run.origin_message&.public_id,
        "kind" => process_run.kind,
        "lifecycle_state" => process_run.lifecycle_state,
        "command_line" => process_run.command_line,
        "timeout_seconds" => process_run.timeout_seconds,
        "metadata" => process_run.metadata,
        "started_at" => process_run.started_at&.iso8601(6),
        "ended_at" => process_run.ended_at&.iso8601(6),
        "created_at" => process_run.created_at&.iso8601(6),
        "updated_at" => process_run.updated_at&.iso8601(6),
      }.compact
    end

    def serialize_subagent_session(session)
      {
        "subagent_session_id" => session.public_id,
        "owner_conversation_id" => session.owner_conversation.public_id,
        "conversation_id" => session.conversation.public_id,
        "origin_turn_id" => session.origin_turn&.public_id,
        "parent_subagent_session_id" => session.parent_subagent_session&.public_id,
        "scope" => session.scope,
        "profile_key" => session.profile_key,
        "depth" => session.depth,
        "close_state" => session.close_state,
        "observed_status" => session.observed_status,
        "close_outcome_kind" => session.close_outcome_kind,
        "close_outcome_payload" => session.close_outcome_payload,
        "created_at" => session.created_at&.iso8601(6),
        "updated_at" => session.updated_at&.iso8601(6),
      }.compact
    end

    def serialize_usage_event(event)
      {
        "conversation_id" => @conversation.public_id,
        "turn_id" => turn_public_id_map[event.turn_id],
        "user_id" => user_public_id_map[event.user_id],
        "workspace_id" => workspace_public_id_map[event.workspace_id],
        "agent_deployment_id" => agent_deployment_public_id_map[event.agent_deployment_id],
        "provider_handle" => event.provider_handle,
        "model_ref" => event.model_ref,
        "operation_kind" => event.operation_kind,
        "success" => event.success,
        "input_tokens" => event.input_tokens,
        "output_tokens" => event.output_tokens,
        "media_units" => event.media_units,
        "estimated_cost" => event.estimated_cost&.to_s("F"),
        "latency_ms" => event.latency_ms,
        "workflow_node_key" => event.workflow_node_key,
        "occurred_at" => event.occurred_at&.iso8601(6),
        "created_at" => event.created_at&.iso8601(6),
        "updated_at" => event.updated_at&.iso8601(6),
      }.compact
    end
  end
end
