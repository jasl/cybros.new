module AgentControl
  module RealtimeLinks
    class Open
      def self.call(...)
        new(...).call
      end

      def initialize(agent_definition_version: nil, agent_connection: nil, execution_runtime_connection: nil, occurred_at: Time.current)
        @agent_definition_version = agent_definition_version
        @agent_connection = agent_connection
        @execution_runtime_connection = execution_runtime_connection
        @occurred_at = occurred_at
      end

      def call
        return open_execution_runtime_connection! if @execution_runtime_connection.present?

        session = resolved_agent_connection
        raise ActiveRecord::RecordNotFound, "Couldn't find AgentConnection" if session.blank?

        session.update!(
          endpoint_metadata: session.endpoint_metadata.merge("realtime_link_connected" => true),
          control_activity_state: "active",
          last_control_activity_at: @occurred_at
        )
        PublishPending.call(agent_definition_version: @agent_definition_version, agent_connection: session, occurred_at: @occurred_at)
        @agent_definition_version
      end

      private

      def resolved_agent_connection
        @agent_connection || @agent_definition_version&.active_agent_connection || @agent_definition_version&.most_recent_agent_connection
      end

      def open_execution_runtime_connection!
        @execution_runtime_connection.update!(
          endpoint_metadata: @execution_runtime_connection.endpoint_metadata.merge("realtime_link_connected" => true)
        )
        PublishPending.call(execution_runtime_connection: @execution_runtime_connection, occurred_at: @occurred_at)
        @execution_runtime_connection
      end
    end
  end
end
