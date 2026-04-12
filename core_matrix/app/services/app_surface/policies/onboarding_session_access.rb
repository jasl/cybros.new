module AppSurface
  module Policies
    class OnboardingSessionAccess
      def self.call(...)
        new(...).call
      end

      def initialize(user:, onboarding_session:)
        @user = user
        @onboarding_session = onboarding_session
      end

      def call
        AppSurface::Policies::AdminAccess.call(
          user: @user,
          installation: @onboarding_session.installation
        )
      end
    end
  end
end
