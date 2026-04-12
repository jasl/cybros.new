module AppSurface
  module Presenters
    class OnboardingSessionPresenter
      def self.call(...)
        new(...).call
      end

      def initialize(onboarding_session:)
        @onboarding_session = onboarding_session
      end

      def call
        {
          "onboarding_session_id" => @onboarding_session.public_id,
          "target_kind" => @onboarding_session.target_kind,
          "target_agent_id" => @onboarding_session.target_agent&.public_id,
          "target_execution_runtime_id" => @onboarding_session.target_execution_runtime&.public_id,
          "issued_by_user_id" => @onboarding_session.issued_by_user&.public_id,
          "status" => @onboarding_session.status,
          "issued_at" => @onboarding_session.issued_at&.iso8601(6),
          "expires_at" => @onboarding_session.expires_at&.iso8601(6),
          "revoked_at" => @onboarding_session.revoked_at&.iso8601(6),
          "closed_at" => @onboarding_session.closed_at&.iso8601(6),
        }.compact
      end
    end
  end
end
