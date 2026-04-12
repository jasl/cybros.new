module OnboardingSessions
  class Issue
    def self.call(...)
      new(...).call
    end

    def initialize(installation:, target_kind:, issued_by:, expires_at:, target: nil)
      @installation = installation
      @target_kind = target_kind
      @issued_by = issued_by
      @expires_at = expires_at
      @target = target
    end

    def call
      validate_issuer_installation!
      validate_target_installation!

      ApplicationRecord.transaction do
        onboarding_session = OnboardingSession.issue!(
          installation: @installation,
          target_kind: @target_kind,
          target_agent: target_agent,
          target_execution_runtime: target_execution_runtime,
          issued_by_user: @issued_by,
          expires_at: @expires_at
        )

        AuditLog.record!(
          installation: @installation,
          actor: @issued_by,
          action: "onboarding_session.issued",
          subject: onboarding_session,
          metadata: {
            "target_kind" => @target_kind,
            "target_agent_id" => target_agent&.id,
            "target_execution_runtime_id" => target_execution_runtime&.id,
          }.compact
        )

        onboarding_session
      end
    end

    private

    def validate_issuer_installation!
      return if @issued_by.installation_id == @installation.id

      raise ArgumentError, "issued_by must belong to the same installation"
    end

    def validate_target_installation!
      return if @target.blank?
      return if @target.installation_id == @installation.id

      raise ArgumentError, "target must belong to the same installation"
    end

    def target_agent
      @target if @target_kind == "agent"
    end

    def target_execution_runtime
      @target if @target_kind == "execution_runtime"
    end
  end
end
