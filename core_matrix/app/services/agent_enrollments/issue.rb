module AgentEnrollments
  class Issue
    def self.call(...)
      new(...).call
    end

    def initialize(agent_program:, actor:, expires_at:)
      @agent_program = agent_program
      @actor = actor
      @expires_at = expires_at
    end

    def call
      validate_actor_installation!

      ApplicationRecord.transaction do
        enrollment = AgentEnrollment.issue!(
          installation: @agent_program.installation,
          agent_program: @agent_program,
          expires_at: @expires_at
        )

        AuditLog.record!(
          installation: @agent_program.installation,
          actor: @actor,
          action: "agent_enrollment.issued",
          subject: enrollment,
          metadata: {
            "agent_program_id" => @agent_program.id,
          }
        )

        enrollment
      end
    end

    private

    def validate_actor_installation!
      return if @actor.installation_id == @agent_program.installation_id

      raise ArgumentError, "actor must belong to the same installation"
    end
  end
end
