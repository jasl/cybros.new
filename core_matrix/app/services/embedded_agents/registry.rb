module EmbeddedAgents
  class Registry
    AGENTS = {
      "conversation_title" => "EmbeddedAgents::ConversationTitle::Invoke",
      "conversation_supervision" => "EmbeddedAgents::ConversationSupervision::Invoke",
    }.freeze

    def self.fetch(agent_key)
      AGENTS.fetch(agent_key.to_s) do
        raise Errors::UnknownAgentKey, "unknown embedded agent key #{agent_key}"
      end.constantize
    end
  end
end
