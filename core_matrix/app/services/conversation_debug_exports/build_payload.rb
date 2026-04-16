module ConversationDebugExports
  class BuildPayload
    BUNDLE_KIND = "conversation_debug_export".freeze
    BUNDLE_VERSION = "2026-04-16".freeze

    def self.call(...)
      new(...).call
    end

    def initialize(conversation:)
      @conversation = conversation
    end

    def call
      conversation_snapshot = ConversationDiagnostics::RecomputeConversationSnapshot.call(conversation: @conversation)
      turn_snapshots = TurnDiagnosticsSnapshot
        .where(conversation: @conversation)
        .joins(:turn)
        .includes(:conversation, :turn)
        .order("turns.sequence ASC")

      {
        "bundle_kind" => BUNDLE_KIND,
        "bundle_version" => BUNDLE_VERSION,
        "conversation_payload" => ConversationExports::BuildConversationPayload.call(conversation: @conversation),
        "diagnostics" => {
          "conversation" => serialize_conversation_snapshot(conversation_snapshot),
          "turns" => turn_snapshots.map { |snapshot| serialize_turn_snapshot(snapshot) },
        },
        "workflow_runs" => workflow_runs.map { |workflow_run| serialize_workflow_run(workflow_run) },
        "workflow_nodes" => workflow_nodes.map { |workflow_node| serialize_workflow_node(workflow_node) },
        "workflow_edges" => workflow_edges.map { |workflow_edge| serialize_workflow_edge(workflow_edge) },
        "workflow_node_events" => workflow_node_events.map { |event| serialize_workflow_node_event(event) },
        "workflow_artifacts" => workflow_artifacts.map { |artifact| serialize_workflow_artifact(artifact) },
        "agent_task_runs" => agent_task_runs.map { |task_run| serialize_agent_task_run(task_run) },
        "tool_invocations" => tool_invocations.map { |tool_invocation| serialize_tool_invocation(tool_invocation) },
        "command_runs" => command_runs.map { |command_run| serialize_command_run(command_run) },
        "process_runs" => process_runs.map { |process_run| serialize_process_run(process_run) },
        "subagent_connections" => subagent_connections.map { |session| serialize_subagent_connection(session) },
        "conversation_supervision_sessions" => conversation_supervision_sessions.map { |session| serialize_conversation_supervision_session(session) },
        "conversation_supervision_messages" => conversation_supervision_messages.map { |message| serialize_conversation_supervision_message(message) },
        "usage_events" => usage_events.map { |event| serialize_usage_event(event) },
      }
    end

    private

    def workflow_runs
      @workflow_runs ||= @conversation.workflow_runs
        .preload(:conversation, :turn, :wait_snapshot_document, :workflow_artifacts)
        .order(:created_at, :id)
    end

    def workflow_nodes
      @workflow_nodes ||= WorkflowNode
        .where(workflow_run: workflow_runs)
        .preload(
          :workflow_run,
          :conversation,
          :turn,
          :yielding_workflow_node,
          :opened_human_interaction_request,
          :spawned_subagent_connection
        )
        .order(:created_at, :id)
    end

    def workflow_node_events
      @workflow_node_events ||= WorkflowNodeEvent
        .where(workflow_run: workflow_runs)
        .preload(:workflow_node, :workflow_run, :conversation, :turn)
        .order(:created_at, :id)
    end

    def workflow_edges
      @workflow_edges ||= WorkflowEdge
        .where(workflow_run: workflow_runs)
        .preload(:workflow_run, :from_node, :to_node)
        .order(:created_at, :id)
    end

    def workflow_artifacts
      @workflow_artifacts ||= WorkflowArtifact
        .where(workflow_run: workflow_runs)
        .preload(:workflow_run, :workflow_node, :json_document)
        .order(:created_at, :id)
    end

    def agent_task_runs
      @agent_task_runs ||= AgentTaskRun
        .where(conversation: @conversation)
        .preload(
          :conversation,
          :turn,
          :workflow_run,
          :workflow_node,
          :subagent_connection,
          :origin_turn,
          holder_agent_connection: :agent_definition_version
        )
        .order(:created_at, :id)
    end

    def tool_invocations
      @tool_invocations ||= ToolInvocation
        .where(workflow_node: workflow_nodes)
        .or(
          ToolInvocation
            .where(agent_task_run: agent_task_runs)
        )
        .preload(
          :tool_definition,
          :tool_implementation,
          :tool_binding,
          :workflow_node,
          :agent_task_run,
          :request_document,
          :response_document,
          :error_document,
          :trace_document
        )
        .order(:created_at, :id)
    end

    def command_runs
      @command_runs ||= CommandRun
        .where(workflow_node: workflow_nodes)
        .or(
          CommandRun
            .where(agent_task_run: agent_task_runs)
        )
        .preload(:tool_invocation, :workflow_node, :agent_task_run)
        .order(:created_at, :id)
    end

    def process_runs
      @process_runs ||= ProcessRun
        .where(conversation: @conversation)
        .preload(:conversation, :turn, :origin_message, :workflow_run, :workflow_node)
        .order(:created_at, :id)
    end

    def subagent_connections
      @subagent_connections ||= SubagentConnection
        .where(owner_conversation: @conversation)
        .or(SubagentConnection.where(conversation: @conversation))
        .preload(:owner_conversation, :conversation, :origin_turn, :parent_subagent_connection)
        .order(:created_at, :id)
    end

    def conversation_supervision_sessions
      @conversation_supervision_sessions ||= @conversation.conversation_supervision_sessions
        .preload(:target_conversation, :initiator)
        .order(:created_at, :id)
    end

    def conversation_supervision_messages
      @conversation_supervision_messages ||= ConversationSupervisionMessage
        .where(conversation_supervision_session: conversation_supervision_sessions)
        .preload(:conversation_supervision_session, :conversation_supervision_snapshot, :target_conversation)
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

    def agent_definition_version_public_id_map
      @agent_definition_version_public_id_map ||= AgentDefinitionVersion
        .where(id: usage_events.map(&:agent_definition_version_id).compact.uniq)
        .pluck(:id, :public_id)
        .to_h
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
        "cached_input_tokens_total" => snapshot.cached_input_tokens_total,
        "prompt_cache_available_event_count" => snapshot.prompt_cache_available_event_count,
        "prompt_cache_unknown_event_count" => snapshot.prompt_cache_unknown_event_count,
        "prompt_cache_unsupported_event_count" => snapshot.prompt_cache_unsupported_event_count,
        "prompt_cache_hit_rate" => prompt_cache_hit_rate(
          cached_input_tokens_total: snapshot.cached_input_tokens_total,
          available_event_count: snapshot.prompt_cache_available_event_count,
          available_input_tokens_total: conversation_prompt_cache_available_input_tokens_total
        ),
        "estimated_cost_total" => snapshot.estimated_cost_total.to_s("F"),
        "estimated_cost_event_count" => snapshot.estimated_cost_event_count,
        "estimated_cost_missing_event_count" => snapshot.estimated_cost_missing_event_count,
        "attributed_user_estimated_cost_event_count" => snapshot.attributed_user_estimated_cost_event_count,
        "attributed_user_estimated_cost_missing_event_count" => snapshot.attributed_user_estimated_cost_missing_event_count,
        "provider_round_count" => snapshot.provider_round_count,
        "tool_call_count" => snapshot.tool_call_count,
        "tool_failure_count" => snapshot.tool_failure_count,
        "command_run_count" => snapshot.command_run_count,
        "command_failure_count" => snapshot.command_failure_count,
        "process_run_count" => snapshot.process_run_count,
        "process_failure_count" => snapshot.process_failure_count,
        "subagent_connection_count" => snapshot.subagent_connection_count,
        "resume_attempt_count" => snapshot.resume_attempt_count,
        "retry_attempt_count" => snapshot.retry_attempt_count,
        "most_expensive_turn_id" => snapshot.most_expensive_turn&.public_id,
        "most_rounds_turn_id" => snapshot.most_rounds_turn&.public_id,
        "management" => Conversations::ManagedPolicy.call(conversation: snapshot.conversation),
        "metadata" => public_snapshot_metadata(snapshot.metadata),
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
        "cached_input_tokens_total" => snapshot.cached_input_tokens_total,
        "prompt_cache_available_event_count" => snapshot.prompt_cache_available_event_count,
        "prompt_cache_unknown_event_count" => snapshot.prompt_cache_unknown_event_count,
        "prompt_cache_unsupported_event_count" => snapshot.prompt_cache_unsupported_event_count,
        "prompt_cache_hit_rate" => prompt_cache_hit_rate(
          cached_input_tokens_total: snapshot.cached_input_tokens_total,
          available_event_count: snapshot.prompt_cache_available_event_count,
          available_input_tokens_total: prompt_cache_available_input_tokens_total_by_turn.fetch(snapshot.turn_id, 0)
        ),
        "estimated_cost_total" => snapshot.estimated_cost_total.to_s("F"),
        "estimated_cost_event_count" => snapshot.estimated_cost_event_count,
        "estimated_cost_missing_event_count" => snapshot.estimated_cost_missing_event_count,
        "attributed_user_estimated_cost_event_count" => snapshot.attributed_user_estimated_cost_event_count,
        "attributed_user_estimated_cost_missing_event_count" => snapshot.attributed_user_estimated_cost_missing_event_count,
        "avg_latency_ms" => snapshot.avg_latency_ms,
        "max_latency_ms" => snapshot.max_latency_ms,
        "provider_round_count" => snapshot.provider_round_count,
        "tool_call_count" => snapshot.tool_call_count,
        "tool_failure_count" => snapshot.tool_failure_count,
        "command_run_count" => snapshot.command_run_count,
        "command_failure_count" => snapshot.command_failure_count,
        "process_run_count" => snapshot.process_run_count,
        "process_failure_count" => snapshot.process_failure_count,
        "subagent_connection_count" => snapshot.subagent_connection_count,
        "resume_attempt_count" => snapshot.resume_attempt_count,
        "retry_attempt_count" => snapshot.retry_attempt_count,
        "pause_state" => snapshot.pause_state,
        "metadata" => public_snapshot_metadata(snapshot.metadata),
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
        "wait_policy_mode" => workflow_run.wait_policy_mode,
        "wait_retry_scope" => workflow_run.wait_retry_scope,
        "wait_resume_mode" => workflow_run.wait_resume_mode,
        "wait_failure_kind" => workflow_run.wait_failure_kind,
        "wait_retry_strategy" => workflow_run.wait_retry_strategy,
        "wait_attempt_no" => workflow_run.wait_attempt_no,
        "wait_max_auto_retries" => workflow_run.wait_max_auto_retries,
        "wait_next_retry_at" => workflow_run.wait_next_retry_at&.iso8601(6),
        "wait_last_error_summary" => workflow_run.wait_last_error_summary,
        "recovery_state" => workflow_run.recovery_state,
        "recovery_reason" => workflow_run.recovery_reason,
        "recovery_drift_reason" => workflow_run.recovery_drift_reason,
        "recovery_agent_task_run_id" => workflow_run.recovery_agent_task_run_public_id,
        "wait_snapshot_document_id" => workflow_run.wait_snapshot_document&.public_id,
        "blocking_resource_type" => workflow_run.blocking_resource_type,
        "blocking_resource_id" => workflow_run.blocking_resource_id,
        "resume_policy" => workflow_run.resume_policy,
        "resume_metadata" => workflow_run.resume_metadata,
        "resume_batch_id" => workflow_run.resume_batch_id,
        "resume_yielding_node_key" => workflow_run.resume_yielding_node_key,
        "resume_successor_node_key" => workflow_run.resume_successor_node_key,
        "resume_successor_node_type" => workflow_run.resume_successor_node_type,
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
        "intent_id" => workflow_node.intent_id,
        "intent_batch_id" => workflow_node.intent_batch_id,
        "intent_requirement" => workflow_node.intent_requirement,
        "intent_conflict_scope" => workflow_node.intent_conflict_scope,
        "intent_idempotency_key" => workflow_node.intent_idempotency_key,
        "intent_payload" => workflow_node.intent_payload.presence,
        "opened_human_interaction_request_id" => workflow_node.opened_human_interaction_request&.public_id,
        "spawned_subagent_connection_id" => workflow_node.spawned_subagent_connection&.public_id,
        "provider_round_index" => workflow_node.provider_round_index,
        "prior_tool_node_keys" => workflow_node.prior_tool_node_keys.presence,
        "blocked_retry_failure_kind" => workflow_node.blocked_retry_failure_kind,
        "blocked_retry_attempt_no" => workflow_node.blocked_retry_attempt_no,
        "transcript_side_effect_committed" => workflow_node.transcript_side_effect_committed? ? true : nil,
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

    def serialize_workflow_edge(workflow_edge)
      {
        "workflow_run_id" => workflow_edge.workflow_run.public_id,
        "from_node_id" => workflow_edge.from_node.public_id,
        "from_node_key" => workflow_edge.from_node.node_key,
        "to_node_id" => workflow_edge.to_node.public_id,
        "to_node_key" => workflow_edge.to_node.node_key,
        "ordinal" => workflow_edge.ordinal,
        "requirement" => workflow_edge.requirement,
        "created_at" => workflow_edge.created_at&.iso8601(6),
        "updated_at" => workflow_edge.updated_at&.iso8601(6),
      }.compact
    end

    def serialize_workflow_artifact(artifact)
      stage = artifact.json_document&.payload&.dig("stage") || {}

      {
        "workflow_run_id" => artifact.workflow_run.public_id,
        "workflow_node_id" => artifact.workflow_node.public_id,
        "workflow_node_key" => artifact.workflow_node.node_key,
        "artifact_key" => artifact.artifact_key,
        "artifact_kind" => artifact.artifact_kind,
        "barrier_kind" => stage["completion_barrier"],
        "stage_index" => stage["stage_index"],
        "dispatch_mode" => stage["dispatch_mode"],
        "created_at" => artifact.created_at&.iso8601(6),
        "updated_at" => artifact.updated_at&.iso8601(6),
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
        "holder_agent_definition_version_id" => task_run.holder_agent_definition_version&.public_id,
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
        "provider_format" => tool_invocation.provider_format,
        "stream_output" => tool_invocation.stream_output,
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

    def serialize_subagent_connection(session)
      {
        "subagent_connection_id" => session.public_id,
        "owner_conversation_id" => session.owner_conversation.public_id,
        "conversation_id" => session.conversation.public_id,
        "origin_turn_id" => session.origin_turn&.public_id,
        "parent_subagent_connection_id" => session.parent_subagent_connection&.public_id,
        "scope" => session.scope,
        "profile_key" => session.profile_key,
        "resolved_model_selector_hint" => session.resolved_model_selector_hint,
        "depth" => session.depth,
        "close_state" => session.close_state,
        "observed_status" => session.observed_status,
        "close_outcome_kind" => session.close_outcome_kind,
        "close_outcome_payload" => session.close_outcome_payload,
        "created_at" => session.created_at&.iso8601(6),
        "updated_at" => session.updated_at&.iso8601(6),
      }.compact
    end

    def serialize_conversation_supervision_session(session)
      {
        "supervision_session_id" => session.public_id,
        "target_conversation_id" => session.target_conversation.public_id,
        "initiator_type" => session.initiator_type,
        "initiator_id" => supervision_initiator_public_id(session),
        "lifecycle_state" => session.lifecycle_state,
        "responder_strategy" => session.responder_strategy,
        "capability_policy_snapshot" => session.capability_policy_snapshot,
        "last_snapshot_at" => session.last_snapshot_at&.iso8601(6),
        "closed_at" => session.closed_at&.iso8601(6),
        "created_at" => session.created_at&.iso8601(6),
      }.compact
    end

    def serialize_conversation_supervision_message(message)
      snapshot = message.conversation_supervision_snapshot
      return {} if snapshot.blank?

      {
        "supervision_message_id" => message.public_id,
        "supervision_session_id" => message.conversation_supervision_session.public_id,
        "supervision_snapshot_id" => snapshot.public_id,
        "target_conversation_id" => message.target_conversation.public_id,
        "role" => message.role,
        "content" => message.content,
        "created_at" => message.created_at&.iso8601(6),
      }
    end

    def serialize_usage_event(event)
      {
        "conversation_id" => @conversation.public_id,
        "turn_id" => turn_public_id_map[event.turn_id],
        "user_id" => user_public_id_map[event.user_id],
        "workspace_id" => workspace_public_id_map[event.workspace_id],
        "agent_definition_version_id" => agent_definition_version_public_id_map[event.agent_definition_version_id],
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

    def prompt_cache_available_input_tokens_total_by_turn
      @prompt_cache_available_input_tokens_total_by_turn ||= usage_events.each_with_object(Hash.new(0)) do |event, totals|
        next unless event.prompt_cache_status == "available"
        next if event.turn_id.nil?

        totals[event.turn_id] += event.input_tokens.to_i
      end
    end

    def conversation_prompt_cache_available_input_tokens_total
      @conversation_prompt_cache_available_input_tokens_total ||= usage_events.sum do |event|
        event.prompt_cache_status == "available" ? event.input_tokens.to_i : 0
      end
    end

    def prompt_cache_hit_rate(cached_input_tokens_total:, available_event_count:, available_input_tokens_total:)
      return nil if available_event_count.to_i.zero?
      return nil if available_input_tokens_total.to_i.zero?

      cached_input_tokens_total.to_f / available_input_tokens_total.to_f
    end

    def public_snapshot_metadata(metadata)
      metadata.except("prompt_cache_available_input_tokens_total")
    end

    def supervision_initiator_public_id(session)
      return session.initiator.public_id if session.initiator.respond_to?(:public_id)

      nil
    end
  end
end
