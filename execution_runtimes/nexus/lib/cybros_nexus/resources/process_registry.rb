require "json"
require "time"

module CybrosNexus
  module Resources
    class ProcessRegistry
      Handle = Struct.new(
        :process_run_id,
        :runtime_owner_id,
        :stdin,
        :output,
        :wait_thread,
        :pid,
        :output_thread,
        :watcher_thread,
        :proxy_path,
        :proxy_target_url,
        :lifecycle_state,
        :exit_status,
        :stdout_bytes,
        :stdout_tail,
        :close_request_id,
        :close_mailbox_item_id,
        :close_strictness,
        :close_signal,
        keyword_init: true
      )

      OUTPUT_TAIL_LIMIT_BYTES = 8_192

      def initialize(store:)
        @store = store
        @mutex = Mutex.new
        @handles = {}
        @released_snapshots = {}
      end

      def register(handle)
        @mutex.synchronize do
          @handles[handle.process_run_id] = handle
        end
        persist_handle!(handle)
        handle
      end

      def fetch(process_run_id:)
        @mutex.synchronize do
          @handles[process_run_id]
        end
      end

      def append_output(process_run_id:, text:)
        @mutex.synchronize do
          handle = @handles[process_run_id]
          next @released_snapshots[process_run_id] if handle.nil?

          handle.stdout_bytes += text.to_s.bytesize
          handle.stdout_tail = trim_tail(handle.stdout_tail, text)
          persist_handle!(handle)
          snapshot_for(handle)
        end
      end

      def mark_close_request(process_run_id:, close_request_id:, mailbox_item_id:, strictness:, signal:)
        @mutex.synchronize do
          handle = @handles[process_run_id]
          next nil if handle.nil?

          handle.close_request_id = close_request_id
          handle.close_mailbox_item_id = mailbox_item_id
          handle.close_strictness = strictness
          handle.close_signal = signal
          persist_handle!(handle)
          snapshot_for(handle)
        end
      end

      def transition(process_run_id:, lifecycle_state:, exit_status: nil)
        @mutex.synchronize do
          handle = @handles[process_run_id]
          next @released_snapshots[process_run_id] if handle.nil?

          handle.lifecycle_state = lifecycle_state
          handle.exit_status = exit_status
          persist_handle!(handle)
          snapshot_for(handle)
        end
      end

      def release(process_run_id:)
        snapshot =
          @mutex.synchronize do
            handle = @handles.delete(process_run_id)
            next @released_snapshots[process_run_id] if handle.nil?

            snapshot = snapshot_for(handle)
            @released_snapshots[process_run_id] = snapshot
            snapshot
          end

        snapshot
      end

      def list(runtime_owner_id: nil)
        @mutex.synchronize do
          @handles.values
            .select { |handle| runtime_owner_id.nil? || handle.runtime_owner_id == runtime_owner_id }
            .map { |handle| snapshot_for(handle) }
        end
      end

      def snapshot(process_run_id:)
        @mutex.synchronize do
          handle = @handles[process_run_id]
          handle ? snapshot_for(handle) : @released_snapshots[process_run_id]
        end
      end

      def shutdown
        @mutex.synchronize do
          current = @handles.values
          @handles = {}
          current
        end
      end

      private

      def snapshot_for(handle)
        {
          "process_run_id" => handle.process_run_id,
          "runtime_owner_id" => handle.runtime_owner_id,
          "lifecycle_state" => handle.lifecycle_state,
          "exit_status" => handle.exit_status,
          "stdout_bytes" => handle.stdout_bytes,
          "stdout_tail" => handle.stdout_tail.dup,
          "proxy_path" => handle.proxy_path,
          "proxy_target_url" => handle.proxy_target_url,
          "close_request_id" => handle.close_request_id,
          "close_mailbox_item_id" => handle.close_mailbox_item_id,
          "close_strictness" => handle.close_strictness,
          "close_signal" => handle.close_signal,
        }.compact
      end

      def persist_handle!(handle)
        @store.database.execute(
          <<~SQL,
            INSERT INTO resource_handles (resource_id, resource_type, state, metadata_json, updated_at)
            VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(resource_id) DO UPDATE SET
              resource_type = excluded.resource_type,
              state = excluded.state,
              metadata_json = excluded.metadata_json,
              updated_at = excluded.updated_at
          SQL
          [
            handle.process_run_id,
            "ProcessRun",
            handle.lifecycle_state,
            JSON.generate(
              {
                "runtime_owner_id" => handle.runtime_owner_id,
                "exit_status" => handle.exit_status,
                "stdout_bytes" => handle.stdout_bytes,
                "stdout_tail" => handle.stdout_tail,
                "proxy_path" => handle.proxy_path,
                "proxy_target_url" => handle.proxy_target_url,
                "close_request_id" => handle.close_request_id,
                "close_mailbox_item_id" => handle.close_mailbox_item_id,
                "close_strictness" => handle.close_strictness,
                "close_signal" => handle.close_signal,
              }
            ),
            Time.now.utc.iso8601,
          ]
        )
      end

      def trim_tail(existing, text)
        combined = +"#{sanitize_output_text(existing)}#{sanitize_output_text(text)}"
        bytes = combined.bytes
        return combined if bytes.length <= OUTPUT_TAIL_LIMIT_BYTES

        bytes.last(OUTPUT_TAIL_LIMIT_BYTES).pack("C*").force_encoding(combined.encoding)
      end

      def sanitize_output_text(text)
        sanitized = text.to_s.dup.force_encoding(Encoding::UTF_8)
        sanitized.valid_encoding? ? sanitized : sanitized.scrub
      end
    end
  end
end
