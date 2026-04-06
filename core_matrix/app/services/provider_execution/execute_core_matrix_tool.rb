module ProviderExecution
  class ExecuteCoreMatrixTool
    def self.call(...)
      new(...).call
    end

    def initialize(workflow_node:, tool_call:)
      @workflow_node = workflow_node
      @conversation = workflow_node.conversation
      @turn = workflow_node.turn
      @tool_call = tool_call.deep_stringify_keys
    end

    def call
      case @tool_call.fetch("tool_name")
      when "subagent_spawn"
        SubagentSessions::Spawn.call(
          conversation: @conversation,
          origin_turn: @turn,
          content: arguments.fetch("content"),
          scope: arguments["scope"].presence || "conversation",
          profile_key: arguments["profile_key"],
          task_payload: arguments.fetch("task_payload", {})
        )
      when "subagent_send"
        session = owned_subagent_session!
        message = SubagentSessions::SendMessage.call(
          conversation: session.conversation,
          content: arguments.fetch("content"),
          sender_kind: "owner_agent",
          sender_conversation: @conversation
        )
        {
          "subagent_session_id" => session.public_id,
          "conversation_id" => session.conversation.public_id,
          "message_id" => message.public_id,
        }
      when "subagent_wait"
        SubagentSessions::Wait.call(
          subagent_session: owned_subagent_session!,
          timeout_seconds: arguments.fetch("timeout_seconds")
        )
      when "subagent_close"
        session = SubagentSessions::RequestClose.call(
          subagent_session: owned_subagent_session!,
          request_kind: "subagent_close",
          reason_kind: "subagent_close_requested",
          strictness: arguments["strictness"].presence || "graceful"
        )
        {
          "subagent_session_id" => session.public_id,
          "derived_close_status" => session.derived_close_status,
          "observed_status" => session.observed_status,
          "close_state" => session.close_state,
        }
      when "subagent_list"
        {
          "entries" => SubagentSessions::ListForConversation.call(conversation: @conversation),
        }
      when "conversation_metadata_update"
        conversation_metadata_update
      else
        raise ArgumentError, "unsupported core matrix tool #{@tool_call.fetch("tool_name")}"
      end
    end

    private

    def arguments
      @arguments ||= @tool_call.fetch("arguments", {}).deep_stringify_keys
    end

    def owned_subagent_session!
      @conversation.owned_subagent_sessions.find_by!(
        public_id: arguments.fetch("subagent_session_id")
      )
    end

    def conversation_metadata_update
      requested_attributes = arguments.slice("title", "summary")
      accepted_attributes = {}
      rejected_attributes = {}

      requested_attributes.each do |attribute, value|
        normalized_value, rejection = normalize_metadata_argument(attribute:, value:)
        if rejection.present?
          rejected_attributes[attribute] = rejection
        else
          accepted_attributes[attribute] = normalized_value
        end
      end

      if accepted_attributes.empty? && rejected_attributes.present?
        begin
          Conversations::Metadata::AgentUpdate.call(
            conversation: @conversation,
            **requested_attributes.symbolize_keys
          )
        rescue ActiveRecord::RecordInvalid
          return {
            "conversation_id" => @conversation.public_id,
            "accepted" => {},
            "rejected" => rejected_attributes,
          }
        end
      end

      updated_conversation = Conversations::Metadata::AgentUpdate.call(
        conversation: @conversation,
        **accepted_attributes.symbolize_keys
      )

      result = {
        "conversation_id" => updated_conversation.public_id,
        "accepted" => accepted_attributes,
      }
      result["rejected"] = rejected_attributes if rejected_attributes.present?
      result
    end

    def normalize_metadata_argument(attribute:, value:)
      field = attribute.to_s
      return [nil, "is locked by user"] if field == "title" && @conversation.title_locked?
      return [nil, "is locked by user"] if field == "summary" && @conversation.summary_locked?
      return [nil, "must be a string"] unless value.nil? || value.is_a?(String)
      return [nil, "contains internal metadata content"] if Conversations::Metadata::InternalContentGuard.internal_metadata_content?(value)

      [value, nil]
    end
  end
end
