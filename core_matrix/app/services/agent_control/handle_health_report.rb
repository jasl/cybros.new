module AgentControl
  class HandleHealthReport
    def self.call(...)
      new(...).call
    end

    def initialize(deployment:, payload:, occurred_at: Time.current, **)
      @deployment = deployment
      @payload = payload
      @occurred_at = occurred_at
    end

    def receipt_attributes
      {}
    end

    def call
      @deployment.update!(
        health_status: @payload.fetch("health_status"),
        health_metadata: @payload.fetch("health_metadata", {}),
        last_health_check_at: @occurred_at
      )
    end
  end
end
