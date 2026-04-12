module AppSurface
  module Presenters
    class AgentPresenter
      def self.call(...)
        new(...).call
      end

      def initialize(agent:)
        @agent = agent
      end

      def call
        {
          "agent_id" => @agent.public_id,
          "key" => @agent.key,
          "display_name" => @agent.display_name,
          "visibility" => @agent.visibility,
          "lifecycle_state" => @agent.lifecycle_state,
          "provisioning_origin" => @agent.provisioning_origin,
          "default_execution_runtime_id" => @agent.default_execution_runtime&.public_id,
          "updated_at" => @agent.updated_at&.iso8601(6),
        }.compact
      end
    end
  end
end
