module EmbeddedAgents
  class Registry
    AGENTS = {
      "conversation_observation" => "EmbeddedAgents::ConversationObservation::Invoke",
    }.freeze

    def self.fetch(agent_key)
      AGENTS.fetch(agent_key.to_s) do
        raise Errors::UnknownAgentKey, "unknown embedded agent key #{agent_key}"
      end.constantize
    end
  end
end
