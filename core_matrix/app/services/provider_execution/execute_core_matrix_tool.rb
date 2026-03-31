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
  end
end
