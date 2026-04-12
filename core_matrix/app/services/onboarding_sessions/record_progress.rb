module OnboardingSessions
  class RecordProgress
    def self.call(...)
      new(...).call
    end

    def initialize(onboarding_session:, runtime_registered: false, agent_registered: false, target_execution_runtime: nil, occurred_at: Time.current)
      @onboarding_session = onboarding_session
      @runtime_registered = runtime_registered
      @agent_registered = agent_registered
      @target_execution_runtime = target_execution_runtime
      @occurred_at = occurred_at
    end

    def call
      updates = {
        last_used_at: @occurred_at,
        status: "registered",
      }
      updates[:runtime_registered_at] = @occurred_at if @runtime_registered
      updates[:agent_registered_at] = @occurred_at if @agent_registered
      updates[:target_execution_runtime] = @target_execution_runtime if @target_execution_runtime.present?
      @onboarding_session.update!(updates)
      @onboarding_session
    end
  end
end
