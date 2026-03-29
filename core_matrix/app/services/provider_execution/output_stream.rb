module ProviderExecution
  class OutputStream
    DEFAULT_FLUSH_BYTES = 64

    def self.call(...)
      new(...).call
    end

    def initialize(workflow_node:, flush_bytes: DEFAULT_FLUSH_BYTES)
      @workflow_node = workflow_node
      @workflow_run = workflow_node.workflow_run
      @conversation = workflow_node.conversation
      @turn = workflow_node.turn
      @flush_bytes = flush_bytes
      @buffer = +""
      @sequence = 0
    end

    def start!
      broadcast!("runtime.assistant_output.started", base_payload)
    end

    def push(delta)
      return if delta.blank?

      @buffer << delta
      flush! if should_flush?(delta)
    end

    def complete!(message:)
      flush!
      broadcast!(
        "runtime.assistant_output.completed",
        base_payload.merge(
          "message_id" => message.public_id,
          "content" => message.content.to_s
        )
      )
    end

    def fail!(code:, message:)
      flush!
      broadcast!(
        "runtime.assistant_output.failed",
        base_payload.merge(
          "code" => code,
          "message" => message.to_s
        )
      )
    end

    private

    def flush!
      return if @buffer.empty?

      @sequence += 1
      broadcast!(
        "runtime.assistant_output.delta",
        base_payload.merge(
          "sequence" => @sequence,
          "delta" => @buffer
        )
      )
      @buffer = +""
    end

    def should_flush?(delta)
      @buffer.bytesize >= @flush_bytes || delta.include?("\n")
    end

    def base_payload
      {
        "stream_id" => "turn-output:#{@turn.public_id}",
        "workflow_run_id" => @workflow_run.public_id,
        "workflow_node_id" => @workflow_node.public_id,
      }
    end

    def broadcast!(event_kind, payload)
      ConversationRuntime::Broadcast.call(
        conversation: @conversation,
        turn: @turn,
        event_kind: event_kind,
        payload: payload
      )
    end
  end
end
