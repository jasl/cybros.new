module AppSurface
  module Queries
    module Admin
      class InstallationOverview
        def self.call(...)
          new(...).call
        end

        def initialize(installation:)
          @installation = installation
        end

        def call
          {
            "name" => @installation.name,
            "bootstrap_state" => @installation.bootstrap_state,
            "agents_count" => @installation.agents.count,
            "execution_runtimes_count" => @installation.execution_runtimes.count,
            "onboarding_sessions_count" => @installation.onboarding_sessions.count,
            "updated_at" => @installation.updated_at&.iso8601(6),
          }.compact
        end
      end
    end
  end
end
