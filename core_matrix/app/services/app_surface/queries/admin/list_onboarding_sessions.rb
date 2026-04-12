module AppSurface
  module Queries
    module Admin
      class ListOnboardingSessions
        def self.call(...)
          new(...).call
        end

        def initialize(installation:)
          @installation = installation
        end

        def call
          @installation.onboarding_sessions.order(:issued_at, :id).to_a
        end
      end
    end
  end
end
