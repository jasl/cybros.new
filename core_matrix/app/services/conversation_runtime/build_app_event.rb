module ConversationRuntime
  class BuildAppEvent
    RESOURCE_ID_FIELDS = %w[process_run_id tool_invocation_id agent_task_run_id].freeze
    INTERNAL_PAYLOAD_KEYS = %w[workflow_node_id workflow_run_id].freeze

    def self.call(...)
      new(...).call
    end

    def initialize(conversation:, event_kind:, payload:, turn: nil, occurred_at: Time.current)
      @conversation = conversation
      @event_kind = event_kind
      @payload = payload.deep_stringify_keys
      @turn = turn
      @occurred_at = occurred_at
    end

    def call
      {
        "event_type" => event_type,
        "resource_type" => resource_type,
        "resource_id" => resource_id,
        "conversation_id" => @conversation.public_id,
        "turn_id" => @turn&.public_id,
        "occurred_at" => @occurred_at.iso8601(6),
        "payload" => app_payload,
      }.compact
    end

    private

    def event_type
      "turn.runtime_event.appended"
    end

    def resource_type
      "conversation_turn_runtime_event"
    end

    def resource_id
      RESOURCE_ID_FIELDS.filter_map { |field| @payload[field].presence }.first ||
        @turn&.public_id ||
        @conversation.public_id
    end

    def app_payload
      @payload.except(*INTERNAL_PAYLOAD_KEYS).merge(
        "activity_kind" => activity_kind
      )
    end

    def activity_kind
      return "process_output" if @event_kind == "runtime.process_run.output"
      return "tool_output" if @event_kind == "runtime.tool_invocation.output"
      return "task_started" if @event_kind.end_with?(".started")
      return "task_completed" if @event_kind.end_with?(".completed")
      return "task_failed" if @event_kind.end_with?(".failed")

      "runtime_event"
    end
  end
end
