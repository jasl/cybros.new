module AgentControl
  module RealtimeLinks
    class Open
      def self.call(...)
        new(...).call
      end

      def initialize(agent_snapshot: nil, agent_connection: nil, execution_runtime_connection: nil, occurred_at: Time.current)
        @agent_snapshot = agent_snapshot
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
        PublishPending.call(agent_snapshot: @agent_snapshot, agent_connection: session, occurred_at: @occurred_at)
        @agent_snapshot
      end

      private

      def resolved_agent_connection
        @agent_connection || @agent_snapshot&.active_agent_connection || @agent_snapshot&.most_recent_agent_connection
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
