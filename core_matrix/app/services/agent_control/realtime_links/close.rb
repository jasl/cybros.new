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
        @deployment.update!(realtime_link_state: "disconnected")
        @deployment
      end
    end
  end
end
