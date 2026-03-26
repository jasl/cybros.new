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
        @deployment.update!(
          realtime_link_state: "connected",
          control_activity_state: "active",
          last_control_activity_at: @occurred_at
        )
        PublishPending.call(deployment: @deployment, occurred_at: @occurred_at)
        @deployment
      end
    end
  end
end
