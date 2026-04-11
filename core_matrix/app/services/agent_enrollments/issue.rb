module AgentEnrollments
  class Issue
    def self.call(...)
      new(...).call
    end

    def initialize(agent:, actor:, expires_at:)
      @agent = agent
      @actor = actor
      @expires_at = expires_at
    end

    def call
      validate_actor_installation!

      ApplicationRecord.transaction do
        enrollment = AgentEnrollment.issue!(
          installation: @agent.installation,
          agent: @agent,
          expires_at: @expires_at
        )

        AuditLog.record!(
          installation: @agent.installation,
          actor: @actor,
          action: "agent_enrollment.issued",
          subject: enrollment,
          metadata: {
            "agent_id" => @agent.id,
          }
        )

        enrollment
      end
    end

    private

    def validate_actor_installation!
      return if @actor.installation_id == @agent.installation_id

      raise ArgumentError, "actor must belong to the same installation"
    end
  end
end
