module Processes
  class BroadcastRuntimeEvent
    def self.call(...)
      new(...).call
    end

    def initialize(process_run:, event_kind:, payload: {}, occurred_at: Time.current)
      @process_run = process_run
      @event_kind = event_kind
      @payload = payload
      @occurred_at = occurred_at
    end

    def call
      ConversationRuntime::Broadcast.call(
        conversation: @process_run.conversation,
        turn: @process_run.turn,
        event_kind: @event_kind,
        occurred_at: @occurred_at,
        payload: base_payload.merge(@payload)
      )
    end

    private

    def base_payload
      {
        "process_run_id" => @process_run.public_id,
        "kind" => @process_run.kind,
        "lifecycle_state" => @process_run.lifecycle_state,
      }
    end
  end
end
