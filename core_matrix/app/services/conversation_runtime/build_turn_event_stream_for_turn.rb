module ConversationRuntime
  class BuildTurnEventStreamForTurn
    def self.call(...)
      new(...).call
    end

    def initialize(conversation:, turn:)
      @conversation = conversation
      @turn = turn
    end

    def call
      BuildTurnEventStream.call(
        conversation_id: @conversation.public_id,
        turn_id: @turn.public_id,
        phase_events: [],
        workflow_node_events: workflow_node_events.map { |event| serialize_workflow_node_event(event) },
        usage_events: usage_events.map { |event| serialize_usage_event(event) },
        tool_invocations: tool_invocations.map { |invocation| serialize_tool_invocation(invocation) },
        command_runs: command_runs.map { |command_run| serialize_command_run(command_run) },
        process_runs: process_runs.map { |process_run| serialize_process_run(process_run) },
        subagent_connections: subagent_connections.map { |session| serialize_subagent_connection(session) },
        subagent_runtime_snapshots: [],
        agent_task_runs: agent_task_runs.map { |task_run| serialize_agent_task_run(task_run) },
        supervision_trace: {},
        summary: {}
      )
    end

    private

    def workflow_runs
      @workflow_runs ||= @conversation.workflow_runs.where(turn: @turn).order(:created_at, :id)
    end

    def workflow_nodes
      @workflow_nodes ||= WorkflowNode.where(workflow_run: workflow_runs).order(:ordinal, :id)
    end

    def workflow_node_events
      @workflow_node_events ||= WorkflowNodeEvent
        .where(workflow_run: workflow_runs)
        .includes(workflow_node: { tool_invocations: :tool_definition }, workflow_run: [], conversation: [], turn: [])
        .order(:created_at, :workflow_node_ordinal, :ordinal)
    end

    def tool_invocations
      @tool_invocations ||= ToolInvocation
        .where(workflow_node: workflow_nodes)
        .includes(:tool_definition, :tool_binding, :tool_implementation, :workflow_node, :agent_task_run)
        .order(:created_at, :id)
    end

    def command_runs
      @command_runs ||= CommandRun
        .where(workflow_node: workflow_nodes)
        .includes(:workflow_node, :tool_invocation, :agent_task_run)
        .order(:created_at, :id)
    end

    def process_runs
      @process_runs ||= ProcessRun
        .where(conversation: @conversation, turn: @turn)
        .includes(:workflow_node)
        .order(:created_at, :id)
    end

    def agent_task_runs
      @agent_task_runs ||= AgentTaskRun
        .where(conversation: @conversation, turn: @turn)
        .includes(:workflow_run, :workflow_node, :subagent_connection, :origin_turn)
        .order(:created_at, :id)
    end

    def usage_events
      @usage_events ||= UsageEvent.where(conversation_id: @conversation.id, turn_id: @turn.id).order(:occurred_at, :id)
    end

    def subagent_connections
      @subagent_connections ||= SubagentConnection
        .where(owner_conversation: @conversation, origin_turn: @turn)
        .or(SubagentConnection.where(conversation: @conversation, origin_turn: @turn))
        .order(:created_at, :id)
    end

    def serialize_workflow_node_event(event)
      payload_tool_invocation_id = event.payload["tool_invocation_id"]
      tool_invocation = event.workflow_node.tool_invocations.find do |candidate|
        payload_tool_invocation_id.present? ? candidate.public_id == payload_tool_invocation_id : true
      end

      {
        "workflow_node_public_id" => event.workflow_node.public_id,
        "workflow_run_public_id" => event.workflow_run.public_id,
        "conversation_id" => event.conversation&.public_id,
        "turn_id" => event.turn&.public_id,
        "workflow_node_key" => event.workflow_node_key,
        "workflow_node_ordinal" => event.workflow_node_ordinal,
        "event_kind" => event.event_kind,
        "ordinal" => event.ordinal,
        "presentation_policy" => event.presentation_policy,
        "payload" => event.payload,
        "node_type" => event.workflow_node.node_type,
        "tool_name" => tool_invocation&.tool_definition&.tool_name,
        "created_at" => event.created_at&.iso8601(6),
        "updated_at" => event.updated_at&.iso8601(6),
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
        "trace_payload" => tool_invocation.trace_payload,
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
        "workflow_node_key" => command_run.workflow_node&.node_key,
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
        "workflow_node_key" => process_run.workflow_node.node_key,
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

    def serialize_subagent_connection(session)
      {
        "subagent_connection_id" => session.public_id,
        "owner_conversation_id" => session.owner_conversation.public_id,
        "conversation_id" => session.conversation.public_id,
        "origin_turn_id" => session.origin_turn&.public_id,
        "profile_key" => session.profile_key,
        "scope" => session.scope,
        "observed_status" => session.observed_status,
        "created_at" => session.created_at&.iso8601(6),
        "updated_at" => session.updated_at&.iso8601(6),
      }.compact
    end

    def serialize_agent_task_run(task_run)
      {
        "agent_task_run_id" => task_run.public_id,
        "workflow_run_id" => task_run.workflow_run.public_id,
        "workflow_node_id" => task_run.workflow_node.public_id,
        "conversation_id" => task_run.conversation.public_id,
        "turn_id" => task_run.turn.public_id,
        "subagent_connection_id" => task_run.subagent_connection&.public_id,
        "origin_turn_id" => task_run.origin_turn&.public_id,
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

    def serialize_usage_event(event)
      {
        "conversation_id" => @conversation.public_id,
        "turn_id" => @turn.public_id,
        "provider_handle" => event.provider_handle,
        "model_ref" => event.model_ref,
        "operation_kind" => event.operation_kind,
        "success" => event.success,
        "input_tokens" => event.input_tokens,
        "output_tokens" => event.output_tokens,
        "prompt_cache_status" => event.prompt_cache_status,
        "cached_input_tokens" => event.cached_input_tokens,
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
