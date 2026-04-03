module Turns
  class FreezeProgramVersion
    def self.call(...)
      new(...).call
    end

    def initialize(conversation:)
      @conversation = conversation
    end

    def call
      agent_session = AgentSession.find_by(agent_program: @conversation.agent_program, lifecycle_state: "active")
      return agent_session.agent_program_version if agent_session.present?

      @conversation.errors.add(:agent_program, "must have an active agent session for turn entry")
      raise ActiveRecord::RecordInvalid, @conversation
    end
  end
end
