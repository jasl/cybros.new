module PairingSessions
  class RecordProgress
    def self.call(...)
      new(...).call
    end

    def initialize(pairing_session:, runtime_registered: false, agent_registered: false, occurred_at: Time.current)
      @pairing_session = pairing_session
      @runtime_registered = runtime_registered
      @agent_registered = agent_registered
      @occurred_at = occurred_at
    end

    def call
      updates = { last_used_at: @occurred_at }
      updates[:runtime_registered_at] = @occurred_at if @runtime_registered
      updates[:agent_registered_at] = @occurred_at if @agent_registered
      @pairing_session.update!(updates)
      @pairing_session
    end
  end
end
