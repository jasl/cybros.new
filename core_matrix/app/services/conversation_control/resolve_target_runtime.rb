module ConversationControl
  class ResolveTargetRuntime
    CONVERSATION_REQUEST_KINDS = %w[
      request_status_refresh
      request_turn_interrupt
      request_conversation_close
      send_guidance_to_active_agent
    ].freeze
    SUBAGENT_REQUEST_KINDS = %w[
      send_guidance_to_subagent
      request_subagent_close
    ].freeze
    WORKFLOW_REQUEST_KINDS = %w[
      resume_waiting_workflow
      retry_blocked_step
    ].freeze

    Result = Struct.new(
      :conversation,
      :request_kind,
      :request_payload,
      :target_record,
      :target_kind,
      :target_public_id,
      :active_turn,
      :workflow_run,
      :subagent_connection,
      :agent_definition_version,
      keyword_init: true
    )

    def self.call(...)
      new(...).call
    end

    def self.target_kind_for(request_kind)
      request_kind = request_kind.to_s
      return "conversation" if CONVERSATION_REQUEST_KINDS.include?(request_kind)
      return "subagent_connection" if SUBAGENT_REQUEST_KINDS.include?(request_kind)
      return "workflow_run" if WORKFLOW_REQUEST_KINDS.include?(request_kind)

      raise ArgumentError, "unsupported conversation control request #{request_kind}"
    end

    def initialize(conversation:, request_kind:, request_payload:)
      @conversation = conversation
      @request_kind = request_kind.to_s
      @request_payload = request_payload.deep_stringify_keys
    end

    def call
      case self.class.target_kind_for(@request_kind)
      when "conversation"
        build_conversation_result
      when "subagent_connection"
        build_subagent_result
      when "workflow_run"
        build_workflow_result
      else
        raise ArgumentError, "unsupported conversation control request #{@request_kind}"
      end
    end

    private

    def build_conversation_result
      Result.new(
        conversation: @conversation,
        request_kind: @request_kind,
        request_payload: @request_payload,
        target_record: @conversation,
        target_kind: "conversation",
        target_public_id: @conversation.public_id,
        active_turn: active_turn,
        workflow_run: active_workflow_run,
        agent_definition_version: resolved_agent_definition_version
      )
    end

    def build_subagent_result
      subagent_connection = requested_subagent_connection

      Result.new(
        conversation: @conversation,
        request_kind: @request_kind,
        request_payload: @request_payload,
        target_record: subagent_connection,
        target_kind: "subagent_connection",
        target_public_id: subagent_connection&.public_id,
        active_turn: active_turn,
        workflow_run: active_workflow_run,
        subagent_connection: subagent_connection,
        agent_definition_version: resolved_agent_definition_version
      )
    end

    def build_workflow_result
      workflow_run = active_workflow_run

      Result.new(
        conversation: @conversation,
        request_kind: @request_kind,
        request_payload: @request_payload,
        target_record: workflow_run,
        target_kind: "workflow_run",
        target_public_id: workflow_run&.public_id,
        active_turn: workflow_run&.turn || active_turn,
        workflow_run: workflow_run,
        agent_definition_version: resolved_agent_definition_version
      )
    end

    def active_turn
      @active_turn ||= begin
        anchored_turn = @conversation.latest_active_turn
        if anchored_turn&.active?
          anchored_turn
        else
          @conversation.turns.where(lifecycle_state: "active").order(:created_at, :id).last
        end
      end
    end

    def active_workflow_run
      @active_workflow_run ||= begin
        anchored_workflow_run = @conversation.latest_active_workflow_run
        if anchored_workflow_run&.active?
          anchored_workflow_run
        else
          @conversation.workflow_runs.where(lifecycle_state: "active").order(:created_at, :id).last
        end
      end
    end

    def requested_subagent_connection
      scope = @conversation.owned_subagent_connections.close_pending_or_open.order(:created_at, :id)
      subagent_connection_id = @request_payload["subagent_connection_id"].presence
      return scope.find_by(public_id: subagent_connection_id) if subagent_connection_id.present?

      scope.detect { |session| !session.terminal_for_wait? } || scope.last
    end

    def resolved_agent_definition_version
      active_agent_connection&.agent_definition_version ||
        active_turn&.agent_definition_version ||
        active_workflow_run&.turn&.agent_definition_version ||
        @conversation.latest_turn&.agent_definition_version ||
        @conversation.turns.order(:created_at, :id).last&.agent_definition_version
    end

    def active_agent_connection
      @active_agent_connection ||= AgentConnection.find_by(
        agent: @conversation.agent,
        lifecycle_state: "active"
      )
    end
  end
end
