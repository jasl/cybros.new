module AgentControl
  module RealtimeLinks
    class Close
      def self.call(...)
        new(...).call
      end

      def initialize(deployment:)
        @deployment = deployment
      end

      def call
        session = @deployment.active_agent_session || @deployment.most_recent_agent_session
        raise ActiveRecord::RecordNotFound, "Couldn't find AgentSession" if session.blank?

        session.update!(
          endpoint_metadata: session.endpoint_metadata.merge("realtime_link_connected" => false),
          control_activity_state: "idle"
        )
        @deployment
      end
    end
  end
end
