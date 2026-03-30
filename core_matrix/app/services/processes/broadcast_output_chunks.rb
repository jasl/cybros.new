module Processes
  class BroadcastOutputChunks
    def self.call(...)
      new(...).call
    end

    def initialize(process_run:, output_chunks:, occurred_at: Time.current)
      @process_run = process_run
      @output_chunks = output_chunks
      @occurred_at = occurred_at
    end

    def call
      Array(@output_chunks).each do |chunk|
        chunk_payload = chunk.to_h.deep_stringify_keys
        next if chunk_payload["text"].blank?

        Processes::BroadcastRuntimeEvent.call(
          process_run: @process_run,
          event_kind: "runtime.process_run.output",
          occurred_at: @occurred_at,
          payload: chunk_payload.slice("stream", "text", "encoding")
        )
      end
    end
  end
end
