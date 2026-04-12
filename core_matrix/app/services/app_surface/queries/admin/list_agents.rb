module AppSurface
  module Queries
    module Admin
      class ListAgents
        def self.call(...)
          new(...).call
        end

        def initialize(installation:)
          @installation = installation
        end

        def call
          @installation.agents.order(:display_name, :id).to_a
        end
      end
    end
  end
end
