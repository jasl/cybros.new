module AgentControl
  module RealtimeLinks
    class Close
      def self.call(...)
        new(...).call
      end

      def initialize(agent_definition_version: nil, agent_connection: nil, execution_runtime_connection: nil)
        @agent_definition_version = agent_definition_version
        @agent_connection = agent_connection
        @execution_runtime_connection = execution_runtime_connection
      end

      def call
        return close_execution_runtime_connection! if @execution_runtime_connection.present?

        session = @agent_connection || @agent_definition_version&.active_agent_connection || @agent_definition_version&.most_recent_agent_connection
        raise ActiveRecord::RecordNotFound, "Couldn't find AgentConnection" if session.blank?

        session.update!(
          endpoint_metadata: session.endpoint_metadata.merge("realtime_link_connected" => false),
          control_activity_state: "idle"
        )
        @agent_definition_version
      end

      private

      def close_execution_runtime_connection!
        @execution_runtime_connection.update!(
          endpoint_metadata: @execution_runtime_connection.endpoint_metadata.merge("realtime_link_connected" => false)
        )
        @execution_runtime_connection
      end
    end
  end
end
