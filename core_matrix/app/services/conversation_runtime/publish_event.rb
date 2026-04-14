module ConversationRuntime
  class PublishEvent
    STREAM_KEY_FIELDS = {
      "runtime.workflow_node." => "workflow_node_id",
      "runtime.agent_task." => "agent_task_run_id",
      "runtime.process_run." => "process_run_id",
      "runtime.tool_invocation." => "tool_invocation_id",
      "runtime.assistant_tool_call." => "stream_id",
    }.freeze
    REDACTED_PAYLOAD_KEYS = {
      "runtime.process_run.output" => %w[text],
      "runtime.tool_invocation.output" => %w[text],
    }.freeze

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
      Broadcast.call(
        conversation: @conversation,
        turn: @turn,
        event_kind: @event_kind,
        payload: @payload,
        occurred_at: @occurred_at
      )

      return unless persistable?

      ConversationEvents::Project.call(
        conversation: @conversation,
        turn: @turn,
        event_kind: @event_kind,
        stream_key: stream_key,
        payload: projected_payload
      )
    end

    private

    def persistable?
      stream_key.present?
    end

    def stream_key
      @stream_key ||=
        STREAM_KEY_FIELDS.each_with_object(nil) do |(prefix, id_field), memo|
          next unless @event_kind.start_with?(prefix)
          next if @payload[id_field].blank?

          break "#{prefix.delete_suffix(".")}:#{@payload.fetch(id_field)}"
        end
    end

    def projected_payload
      @payload.except(*Array(REDACTED_PAYLOAD_KEYS[@event_kind]))
    end
  end
end
