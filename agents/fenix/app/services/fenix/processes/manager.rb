module Fenix
  module Processes
    class Manager
      # Long-lived process handles are runtime-local projections of kernel-owned
      # ProcessRun records. They are useful for close/output delivery, but they
      # are intentionally not a durable fact source.
      LocalHandle = Struct.new(
        :process_run_id,
        :stdin,
        :stdout,
        :stderr,
        :wait_thread,
        :control_client,
        :stdout_thread,
        :stderr_thread,
        :watcher_thread,
        :close_request_id,
        :strictness,
        :terminal_reported,
        keyword_init: true
      )

      class << self
        OUTPUT_READ_SIZE = 4096

        def register(process_run_id:, stdin:, stdout:, stderr:, wait_thread:, control_client: nil, start_monitoring: true)
          entry = LocalHandle.new(
            process_run_id: process_run_id,
            stdin: stdin,
            stdout: stdout,
            stderr: stderr,
            wait_thread: wait_thread,
            control_client: control_client || Fenix::Runtime::ControlPlane.client,
            terminal_reported: false
          )

          synchronize do
            entries[process_run_id] = entry
          end

          start_monitoring!(entry) if start_monitoring
          entry
        end

        def spawn!(process_run_id:, command_line:, control_client: nil)
          stdin, stdout, stderr, wait_thread = Open3.popen3("/bin/sh", "-lc", command_line.to_s)
          entry = register(
            process_run_id: process_run_id,
            stdin: stdin,
            stdout: stdout,
            stderr: stderr,
            wait_thread: wait_thread,
            control_client: control_client,
            start_monitoring: false
          )

          report_started!(entry)
          start_monitoring!(entry)
          entry
        rescue StandardError => error
          cleanup_failed_spawn!(entry:, process_run_id:, control_client:, error:)
          raise
        end

        def lookup(process_run_id:)
          synchronize do
            entries[process_run_id]
          end
        end

        def close!(mailbox_item:, deliver_reports:, control_client: nil)
          mailbox_item = mailbox_item.deep_stringify_keys
          process_run_id = mailbox_item.dig("payload", "resource_id")
          entry = lookup(process_run_id: process_run_id)

          return handle_missing_entry!(mailbox_item: mailbox_item, deliver_reports: deliver_reports, control_client: control_client) if entry.nil?

          strictness = mailbox_item.dig("payload", "strictness").presence || "graceful"
          client = control_client || entry.control_client

          synchronize do
            entry.control_client = client if client.present?
            entry.close_request_id = mailbox_item.fetch("item_id")
            entry.strictness = strictness
          end

          report_acknowledged!(mailbox_item: mailbox_item, control_client: client) if deliver_reports && client.present?
          signal_process(entry, strictness: strictness)
          :handled
        end

        def prune_terminated_handles!
          stale_entries = synchronize do
            entries.values.select do |entry|
              wait_thread = entry.wait_thread
              wait_thread.nil? || !wait_thread.alive?
            end
          end

          stale_entries.each do |entry|
            cleanup_entry(entry)
            join_thread(entry.wait_thread)
            join_thread(entry.stdout_thread)
            join_thread(entry.stderr_thread)
            join_thread(entry.watcher_thread)
          end

          stale_entries.length
        end

        def reset!
          current_entries = synchronize do
            entries.values.tap { entries.clear }
          end

          current_entries.each do |entry|
            terminate_process(entry, signal: "KILL")
            close_io(entry.stdin)
            close_io(entry.stdout)
            close_io(entry.stderr)
            join_thread(entry.stdout_thread)
            join_thread(entry.stderr_thread)
            join_thread(entry.watcher_thread)
          end
        end

        private

        def handle_missing_entry!(mailbox_item:, deliver_reports:, control_client:)
          if deliver_reports && control_client.present?
            control_client.report!(
              payload: base_close_report(mailbox_item: mailbox_item, method_id: "resource_close_failed").merge(
                "close_outcome_kind" => "residual_abandoned",
                "close_outcome_payload" => {
                  "source" => "fenix_process_manager",
                  "reason" => "process_handle_missing",
                }
              )
            )
          end

          :handled
        end

        def start_output_thread(entry, stream:, io:)
          Thread.new do
            Thread.current.abort_on_exception = false

            loop do
              chunk = io.readpartial(OUTPUT_READ_SIZE)
              next if chunk.blank?

              report_output_chunk(entry, stream: stream, text: chunk)
            end
          rescue EOFError, IOError
            nil
          end
        end

        def report_output_chunk(entry, stream:, text:)
          entry.control_client&.report!(
            payload: {
              "method_id" => "process_output",
              "protocol_message_id" => "fenix-process-output-#{SecureRandom.uuid}",
              "resource_type" => "ProcessRun",
              "resource_id" => entry.process_run_id,
              "output_chunks" => [
                {
                  "stream" => stream,
                  "text" => text,
                },
              ],
            }
          )
        rescue StandardError
          nil
        end

        def start_watcher_thread(entry)
          Thread.new do
            Thread.current.abort_on_exception = false
            status = entry.wait_thread.value
            report_terminal_close(entry, exit_status: status&.exitstatus)
          rescue IOError, Errno::ECHILD
            report_terminal_close(entry, exit_status: nil)
          ensure
            cleanup_entry(entry)
          end
        end

        def report_terminal_close(entry, exit_status:)
          terminal_context =
            synchronize do
              next nil if entry.terminal_reported

              entry.terminal_reported = true
              {
                "close_request_id" => entry.close_request_id,
                "strictness" => entry.strictness.presence || "graceful",
                "control_client" => entry.control_client,
              }
            end
          return if terminal_context.nil? || terminal_context["control_client"].blank?

          if terminal_context["close_request_id"].present?
            terminal_context["control_client"].report!(
              payload: {
                "method_id" => "resource_closed",
                "protocol_message_id" => "fenix-process-close-#{SecureRandom.uuid}",
                "mailbox_item_id" => terminal_context.fetch("close_request_id"),
                "close_request_id" => terminal_context.fetch("close_request_id"),
                "resource_type" => "ProcessRun",
                "resource_id" => entry.process_run_id,
                "close_outcome_kind" => terminal_context.fetch("strictness") == "forced" ? "forced" : "graceful",
                "close_outcome_payload" => {
                  "source" => "fenix_process_manager",
                  "exit_status" => exit_status,
                }.compact,
              }
            )
          else
            terminal_context["control_client"].report!(
              payload: {
                "method_id" => "process_exited",
                "protocol_message_id" => "fenix-process-exited-#{SecureRandom.uuid}",
                "resource_type" => "ProcessRun",
                "resource_id" => entry.process_run_id,
                "lifecycle_state" => exit_status.to_i.zero? ? "stopped" : "failed",
                "exit_status" => exit_status,
                "metadata" => {
                  "source" => "fenix_process_manager",
                  "reason" => "natural_exit",
                },
              }
            )
          end
        rescue StandardError
          nil
        end

        def report_started!(entry)
          entry.control_client&.report!(
            payload: {
              "method_id" => "process_started",
              "protocol_message_id" => "fenix-process-started-#{SecureRandom.uuid}",
              "resource_type" => "ProcessRun",
              "resource_id" => entry.process_run_id,
            }
          )
        end

        def start_monitoring!(entry)
          entry.stdout_thread = start_output_thread(entry, stream: "stdout", io: entry.stdout)
          entry.stderr_thread = start_output_thread(entry, stream: "stderr", io: entry.stderr)
          entry.watcher_thread = start_watcher_thread(entry)
        end

        def cleanup_failed_spawn!(entry:, process_run_id:, control_client:, error:)
          terminate_process(entry, signal: "KILL") if entry.present?
          close_io(entry&.stdin)
          close_io(entry&.stdout)
          close_io(entry&.stderr)
          join_thread(entry&.wait_thread)
          cleanup_entry(entry) if entry.present?

          (entry&.control_client || control_client)&.report!(
            payload: {
              "method_id" => "process_exited",
              "protocol_message_id" => "fenix-process-exited-#{SecureRandom.uuid}",
              "resource_type" => "ProcessRun",
              "resource_id" => process_run_id,
              "lifecycle_state" => "failed",
              "metadata" => {
                "source" => "fenix_process_manager",
                "reason" => "spawn_failed",
                "error_class" => error.class.name,
                "error_message" => error.message,
              },
            }
          )
        rescue StandardError
          nil
        end

        def report_acknowledged!(mailbox_item:, control_client:)
          control_client.report!(
            payload: base_close_report(mailbox_item: mailbox_item, method_id: "resource_close_acknowledged")
          )
        end

        def base_close_report(mailbox_item:, method_id:)
          {
            "method_id" => method_id,
            "protocol_message_id" => "fenix-#{method_id}-#{SecureRandom.uuid}",
            "mailbox_item_id" => mailbox_item.fetch("item_id"),
            "close_request_id" => mailbox_item.fetch("item_id"),
            "resource_type" => mailbox_item.dig("payload", "resource_type"),
            "resource_id" => mailbox_item.dig("payload", "resource_id"),
          }
        end

        def signal_process(entry, strictness:)
          terminate_process(entry, signal: strictness == "forced" ? "KILL" : "TERM")
        end

        def terminate_process(entry, signal:)
          Process.kill(signal, entry.wait_thread.pid)
        rescue Errno::ESRCH, IOError
          nil
        end

        def cleanup_entry(entry)
          synchronize do
            current_entry = entries[entry.process_run_id]
            entries.delete(entry.process_run_id) if current_entry.equal?(entry)
          end

          Fenix::Processes::ProxyRegistry.unregister(process_run_id: entry.process_run_id) if defined?(Fenix::Processes::ProxyRegistry)
          close_io(entry.stdin)
          close_io(entry.stdout)
          close_io(entry.stderr)
        end

        def close_io(io)
          return if io.nil? || io.closed?

          io.close
        rescue IOError
          nil
        end

        def join_thread(thread)
          return if thread.nil? || thread == Thread.current

          thread.join(0.5)
        rescue StandardError
          nil
        end

        def entries
          @entries ||= {}
        end

        def mutex
          @mutex ||= Mutex.new
        end

        def synchronize(&block)
          mutex.synchronize(&block)
        end
      end
    end
  end
end
