module AppSurface
  module Queries
    module Admin
      class ListExecutionRuntimes
        def self.call(...)
          new(...).call
        end

        def initialize(installation:)
          @installation = installation
        end

        def call
          @installation.execution_runtimes.order(:display_name, :id).to_a
        end
      end
    end
  end
end
