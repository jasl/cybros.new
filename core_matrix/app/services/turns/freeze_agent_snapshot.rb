module Turns
  class FreezeAgentSnapshot
    def self.call(...)
      new(...).call
    end

    def initialize(conversation:)
      @conversation = conversation
    end

    def call
      agent_connection = AgentConnection.find_by(agent: @conversation.agent, lifecycle_state: "active")
      return agent_connection.agent_snapshot if agent_connection.present?

      @conversation.errors.add(:agent, "must have an active agent connection for turn entry")
      raise ActiveRecord::RecordInvalid, @conversation
    end
  end
end
