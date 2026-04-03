module AgentControl
  module RealtimeLinks
    class Open
      def self.call(...)
        new(...).call
      end

      def initialize(deployment:, occurred_at: Time.current)
        @deployment = deployment
        @occurred_at = occurred_at
      end

      def call
        session = resolved_agent_session
        raise ActiveRecord::RecordNotFound, "Couldn't find AgentSession" if session.blank?

        session.update!(
          endpoint_metadata: session.endpoint_metadata.merge("realtime_link_connected" => true),
          control_activity_state: "active",
          last_control_activity_at: @occurred_at
        )
        PublishPending.call(deployment: @deployment, agent_session: session, occurred_at: @occurred_at)
        @deployment
      end

      private

      def resolved_agent_session
        @deployment.active_agent_session || @deployment.most_recent_agent_session
      end
    end
  end
end
