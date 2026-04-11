module AgentAPI
  class BaseController < ActionController::API
    include ActionController::HttpAuthentication::Token::ControllerMethods

    before_action :authenticate_agent_connection!

    rescue_from ActiveRecord::RecordInvalid, with: :render_record_invalid
    rescue_from ActiveRecord::RecordNotFound, with: :render_not_found
    rescue_from AgentSnapshots::Register::InvalidEnrollment, with: :render_unprocessable_entity
    rescue_from AgentSnapshots::Register::ExpiredEnrollment, with: :render_unprocessable_entity
    rescue_from AgentSnapshots::Handshake::FingerprintMismatch, with: :render_unprocessable_entity
    rescue_from ExecutionRuntimes::Register::InvalidEnrollment, with: :render_unprocessable_entity
    rescue_from ExecutionRuntimes::Register::ExpiredEnrollment, with: :render_unprocessable_entity
    rescue_from ExecutionRuntimes::Reconcile::MissingExecutionRuntimeFingerprint, with: :render_unprocessable_entity

    private

    attr_reader :current_agent_connection, :current_agent_snapshot, :current_execution_runtime

    def authenticate_agent_connection!
      @current_agent_connection = authenticate_with_http_token do |token, _options|
        AgentConnection.find_by_plaintext_connection_credential(token)
      end
      @current_agent_snapshot = @current_agent_connection&.agent_snapshot
      @current_execution_runtime = @current_agent_connection&.agent&.default_execution_runtime
      return if @current_agent_connection.present?

      render json: { error: "connection credential is invalid" }, status: :unauthorized
    end

    def request_payload
      params.to_unsafe_h.except("controller", "action").deep_stringify_keys
    end

    def find_workspace!(workspace_id)
      Workspace.find_by!(
        public_id: workspace_id,
        installation_id: current_agent_snapshot.installation_id
      )
    end

    def find_conversation!(conversation_id, workspace: nil)
      scope = {
        public_id: conversation_id,
        installation_id: current_agent_snapshot.installation_id,
        deletion_state: "retained",
      }
      scope[:workspace_id] = workspace.id if workspace.present?

      Conversation.find_by!(scope)
    end

    def find_turn!(turn_id)
      Turn.find_by!(
        public_id: turn_id,
        installation_id: current_agent_snapshot.installation_id
      )
    end

    def find_workflow_run!(workflow_run_id)
      WorkflowRun.find_by!(
        public_id: workflow_run_id,
        installation_id: current_agent_snapshot.installation_id
      )
    end

    def find_workflow_node!(workflow_node_id)
      WorkflowNode.find_by!(
        public_id: workflow_node_id,
        installation_id: current_agent_snapshot.installation_id
      )
    end

    def find_agent_task_run!(agent_task_run_id)
      AgentTaskRun.find_by!(
        public_id: agent_task_run_id,
        installation_id: current_agent_snapshot.installation_id
      )
    end

    def find_tool_invocation!(tool_invocation_id)
      ToolInvocation.find_by!(
        public_id: tool_invocation_id,
        installation_id: current_agent_snapshot.installation_id
      )
    end

    def find_command_run!(command_run_id)
      CommandRun.find_by!(
        public_id: command_run_id,
        installation_id: current_agent_snapshot.installation_id
      )
    end

    def authorize_agent_task_run!(agent_task_run)
      agent_task_run = agent_task_run.reload
      raise ActiveRecord::RecordNotFound, "Couldn't find AgentTaskRun" if agent_task_run.agent_id != current_agent_connection.agent_id

      if current_execution_runtime.present?
        raise ActiveRecord::RecordNotFound, "Couldn't find AgentTaskRun" if agent_task_run.turn.execution_runtime_id != current_execution_runtime.id
      end

      return if agent_task_run.holder_agent_connection_id.blank? || agent_task_run.holder_agent_connection_id == current_agent_connection.id

      raise ActiveRecord::RecordNotFound, "Couldn't find AgentTaskRun"
    end

    def authorize_active_agent_task_run!(agent_task_run)
      authorize_agent_task_run!(agent_task_run)
      raise ActiveRecord::RecordNotFound, "Couldn't find AgentTaskRun" unless agent_task_run.running?
      raise ActiveRecord::RecordNotFound, "Couldn't find AgentTaskRun" if agent_task_run.close_requested_at.present?
    end

    def authorize_tool_invocation!(tool_invocation)
      authorize_agent_task_run!(tool_invocation.agent_task_run)
    end

    def authorize_running_tool_invocation!(tool_invocation)
      authorize_tool_invocation!(tool_invocation)
      authorize_active_agent_task_run!(tool_invocation.agent_task_run)
      raise ActiveRecord::RecordNotFound, "Couldn't find ToolInvocation" unless tool_invocation.running?
    end

    def authorize_command_run!(command_run)
      authorize_agent_task_run!(command_run.agent_task_run)
      authorize_tool_invocation!(command_run.tool_invocation)
    end

    def authorize_live_command_run!(command_run)
      authorize_command_run!(command_run)
      authorize_active_agent_task_run!(command_run.agent_task_run)
      raise ActiveRecord::RecordNotFound, "Couldn't find ToolInvocation" unless command_run.tool_invocation.running?
    end

    def find_tool_binding_for_agent_task_run!(agent_task_run, tool_name)
      agent_task_run.tool_bindings
        .joins(:tool_definition)
        .find_by!(tool_definitions: { tool_name: tool_name })
    end

    def serialize_message(message)
      {
        "id" => message.public_id,
        "conversation_id" => message.conversation.public_id,
        "turn_id" => message.turn.public_id,
        "role" => message.role,
        "slot" => message.slot,
        "variant_index" => message.variant_index,
        "content" => message.content,
      }
    end

    def serialize_variable(variable, conversation: nil, scope: nil)
      return if variable.blank?

      if variable.is_a?(CanonicalVariable)
        return {
          "workspace_id" => variable.workspace.public_id,
          "scope" => variable.scope,
          "key" => variable.key,
          "typed_value_payload" => variable.typed_value_payload,
          "source_kind" => variable.source_kind,
          "projection_policy" => variable.projection_policy,
          "current" => variable.current,
        }
      end

      raise ArgumentError, "conversation is required for conversation store serialization" if conversation.blank?

      {
        "workspace_id" => conversation.workspace.public_id,
        "conversation_id" => conversation.public_id,
        "scope" => scope || "conversation",
        "key" => variable.key,
        "typed_value_payload" => variable.respond_to?(:typed_value_payload) ? variable.typed_value_payload : nil,
        "value_type" => variable.respond_to?(:value_type) ? variable.value_type : nil,
        "value_bytesize" => variable.respond_to?(:value_bytesize) ? variable.value_bytesize : nil,
        "current" => true,
      }.compact
    end

    def serialize_variable_metadata(metadata, conversation:)
      {
        "workspace_id" => conversation.workspace.public_id,
        "conversation_id" => conversation.public_id,
        "scope" => "conversation",
        "key" => metadata.key,
        "value_type" => metadata.value_type,
        "value_bytesize" => metadata.value_bytesize,
      }.compact
    end

    def serialize_human_interaction_request(request)
      {
        "request_id" => request.public_id,
        "request_type" => request.type,
        "workflow_run_id" => request.workflow_run.public_id,
        "workflow_node_id" => request.workflow_node.public_id,
        "conversation_id" => request.conversation.public_id,
        "turn_id" => request.turn.public_id,
        "lifecycle_state" => request.lifecycle_state,
        "blocking" => request.blocking,
        "request_payload" => request.request_payload,
        "result_payload" => request.result_payload,
      }
    end

    def serialize_tool_invocation(tool_invocation)
      {
        "tool_invocation_id" => tool_invocation.public_id,
        "agent_task_run_id" => tool_invocation.agent_task_run.public_id,
        "tool_binding_id" => tool_invocation.tool_binding.public_id,
        "tool_definition_id" => tool_invocation.tool_definition.public_id,
        "tool_implementation_id" => tool_invocation.tool_implementation.public_id,
        "tool_name" => tool_invocation.tool_definition.tool_name,
        "status" => tool_invocation.status,
        "request_payload" => tool_invocation.request_payload,
        "stream_output" => tool_invocation.stream_output == true,
      }
    end

    def serialize_command_run(command_run)
      {
        "command_run_id" => command_run.public_id,
        "tool_invocation_id" => command_run.tool_invocation.public_id,
        "agent_task_run_id" => command_run.agent_task_run.public_id,
        "lifecycle_state" => command_run.lifecycle_state,
        "command_line" => command_run.command_line,
        "timeout_seconds" => command_run.timeout_seconds,
        "pty" => command_run.pty,
      }
    end

    def serialize_process_run(process_run)
      {
        "process_run_id" => process_run.public_id,
        "workflow_node_id" => process_run.workflow_node.public_id,
        "conversation_id" => process_run.conversation.public_id,
        "turn_id" => process_run.turn.public_id,
        "kind" => process_run.kind,
        "lifecycle_state" => process_run.lifecycle_state,
        "command_line" => process_run.command_line,
        "timeout_seconds" => process_run.timeout_seconds,
      }
    end

    def render_record_invalid(error)
      render json: { error: error.record.errors.full_messages.to_sentence }, status: :unprocessable_entity
    end

    def render_not_found(error)
      render json: { error: error.message }, status: :not_found
    end

    def render_unprocessable_entity(error)
      render json: { error: error.message }, status: :unprocessable_entity
    end
  end
end
