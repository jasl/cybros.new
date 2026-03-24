module AgentEnrollments
  class Issue
    def self.call(...)
      new(...).call
    end

    def initialize(agent_installation:, actor:, expires_at:)
      @agent_installation = agent_installation
      @actor = actor
      @expires_at = expires_at
    end

    def call
      validate_actor_installation!

      ApplicationRecord.transaction do
        enrollment = AgentEnrollment.issue!(
          installation: @agent_installation.installation,
          agent_installation: @agent_installation,
          expires_at: @expires_at
        )

        AuditLog.record!(
          installation: @agent_installation.installation,
          actor: @actor,
          action: "agent_enrollment.issued",
          subject: enrollment,
          metadata: {
            "agent_installation_id" => @agent_installation.id,
          }
        )

        enrollment
      end
    end

    private

    def validate_actor_installation!
      return if @actor.installation_id == @agent_installation.installation_id

      raise ArgumentError, "actor must belong to the same installation"
    end
  end
end
