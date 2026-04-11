require "open3"
require "securerandom"

module Processes
  class Manager
  LocalHandle = Struct.new(
    :process_run_id,
    :runtime_owner_id,
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
    :exit_status,
    :stdout_bytes,
    :stderr_bytes,
    :stdout_tail,
    :stderr_tail,
    keyword_init: true
  )

  class << self
    OUTPUT_READ_SIZE = 4096
    OUTPUT_TAIL_LIMIT_BYTES = 8192

    def register(process_run_id:, runtime_owner_id:, stdin:, stdout:, stderr:, wait_thread:, control_client: nil, start_monitoring: true)
      entry = LocalHandle.new(
        process_run_id: process_run_id,
        runtime_owner_id: runtime_owner_id,
        stdin: stdin,
        stdout: stdout,
        stderr: stderr,
        wait_thread: wait_thread,
        control_client: control_client || Shared::ControlPlane.client,
        terminal_reported: false,
        exit_status: nil,
        stdout_bytes: 0,
        stderr_bytes: 0,
        stdout_tail: +"",
        stderr_tail: +""
      )

      registry.store(entry)

      start_monitoring!(entry) if start_monitoring
      entry
    end

    def spawn!(process_run_id:, runtime_owner_id:, command_line:, control_client: nil, environment: nil)
      stdin, stdout, stderr, wait_thread = Open3.popen3(
        (environment || ENV.to_h),
        "/bin/sh",
        "-lc",
        command_line.to_s
      )
      entry = register(
        process_run_id: process_run_id,
        runtime_owner_id: runtime_owner_id,
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
      registry.lookup(key: process_run_id)
    end

    def append_output(process_run_id:, stream:, text:)
      registry.mutate(key: process_run_id) do |entry|
        bytes = text.to_s.bytesize
        case stream
        when "stdout"
          entry.stdout_bytes += bytes
          entry.stdout_tail = trim_tail(entry.stdout_tail, text)
        when "stderr"
          entry.stderr_bytes += bytes
          entry.stderr_tail = trim_tail(entry.stderr_tail, text)
        else
          raise ArgumentError, "unsupported process stream #{stream}"
        end

        snapshot_for(entry)
      end
    end

    def list(runtime_owner_id: nil)
      registry.project_list(runtime_owner_id: runtime_owner_id) { |entry| snapshot_for(entry) }
    end

    def output_snapshot(process_run_id:)
      registry.project_entry(key: process_run_id) do |entry|
        entry.exit_status ||= exit_status_for(entry) if !entry.wait_thread&.alive?
        snapshot_for(entry)
      end || registry.released_snapshot(process_run_id)
    end

    def proxy_info(process_run_id:)
      proxy_entry = Processes::ProxyRegistry.lookup(process_run_id:)
      return nil if proxy_entry.blank?

      {
        "process_run_id" => process_run_id,
        "proxy_path" => proxy_entry.fetch("path_prefix"),
        "proxy_target_url" => proxy_entry.fetch("target_url"),
      }
    end

    def close!(mailbox_item:, deliver_reports:, control_client: nil)
      mailbox_item = mailbox_item.deep_stringify_keys
      process_run_id = mailbox_item.dig("payload", "resource_id")
      entry = lookup(process_run_id: process_run_id)

      return handle_missing_entry!(mailbox_item: mailbox_item, deliver_reports: deliver_reports, control_client: control_client) if entry.nil?

      strictness = mailbox_item.dig("payload", "strictness").presence || "graceful"
      client = control_client || entry.control_client

      registry.synchronize do
        entry.control_client = client if client.present?
        entry.close_request_id = mailbox_item.fetch("item_id")
        entry.strictness = strictness
      end

      report_acknowledged!(mailbox_item: mailbox_item, control_client: client) if deliver_reports && client.present?
      signal_process(entry, strictness: strictness)
      :handled
    end

    def prune_terminated_handles!
      stale_entries = registry.values.select do |entry|
        wait_thread = entry.wait_thread
        wait_thread.nil? || !wait_thread.alive?
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
      current_entries = registry.clear!

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
              "source" => "nexus_process_manager",
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
      append_output(process_run_id: entry.process_run_id, stream: stream, text: text)
      entry.control_client&.report!(
        payload: {
          "method_id" => "process_output",
          "protocol_message_id" => "nexus-process-output-#{SecureRandom.uuid}",
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
        registry.synchronize do
          next nil if entry.terminal_reported

          entry.terminal_reported = true
          entry.exit_status = exit_status
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
            "protocol_message_id" => "nexus-process-close-#{SecureRandom.uuid}",
            "mailbox_item_id" => terminal_context.fetch("close_request_id"),
            "close_request_id" => terminal_context.fetch("close_request_id"),
            "resource_type" => "ProcessRun",
            "resource_id" => entry.process_run_id,
            "close_outcome_kind" => terminal_context.fetch("strictness") == "forced" ? "forced" : "graceful",
            "close_outcome_payload" => {
              "source" => "nexus_process_manager",
              "exit_status" => exit_status,
            }.compact,
          }
        )
      else
        terminal_context["control_client"].report!(
          payload: {
            "method_id" => "process_exited",
            "protocol_message_id" => "nexus-process-exited-#{SecureRandom.uuid}",
            "resource_type" => "ProcessRun",
            "resource_id" => entry.process_run_id,
            "lifecycle_state" => exit_status.to_i.zero? ? "stopped" : "failed",
            "exit_status" => exit_status,
            "metadata" => {
              "source" => "nexus_process_manager",
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
          "protocol_message_id" => "nexus-process-started-#{SecureRandom.uuid}",
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
          "protocol_message_id" => "nexus-process-exited-#{SecureRandom.uuid}",
          "resource_type" => "ProcessRun",
          "resource_id" => process_run_id,
          "lifecycle_state" => "failed",
          "metadata" => {
            "source" => "nexus_process_manager",
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
        "protocol_message_id" => "nexus-#{method_id}-#{SecureRandom.uuid}",
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
      ::Process.kill(signal, entry.wait_thread.pid)
    rescue Errno::ESRCH, IOError
      nil
    end

    def cleanup_entry(entry)
      join_thread(entry.stdout_thread)
      join_thread(entry.stderr_thread)

      entry.exit_status ||= exit_status_for(entry)
      registry.capture_and_remove(
        key: entry.process_run_id,
        entry: entry,
        snapshot: snapshot_for(entry)
      )

      Processes::ProxyRegistry.unregister(process_run_id: entry.process_run_id)
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

    def snapshot_for(entry)
      return nil if entry.blank?

      {
        "process_run_id" => entry.process_run_id,
        "runtime_owner_id" => entry.runtime_owner_id,
        "lifecycle_state" => entry.wait_thread&.alive? ? "running" : "stopped",
        "exit_status" => entry.exit_status,
        "stdout_bytes" => entry.stdout_bytes,
        "stderr_bytes" => entry.stderr_bytes,
        "stdout_tail" => entry.stdout_tail.dup,
        "stderr_tail" => entry.stderr_tail.dup,
      }.compact.merge(proxy_info(process_run_id: entry.process_run_id) || {})
    end

    def trim_tail(existing, text)
      combined = +"#{existing}#{text}"
      bytes = combined.bytes
      return combined if bytes.length <= OUTPUT_TAIL_LIMIT_BYTES

      bytes.last(OUTPUT_TAIL_LIMIT_BYTES).pack("C*").force_encoding(combined.encoding)
    end

    def registry
      @registry ||= Shared::Values::OwnedResourceRegistry.new(
        key_attr: :process_run_id,
        retain_released_snapshots: true
      )
    end

    def exit_status_for(entry)
      wait_thread = entry.wait_thread
      return nil if wait_thread.nil? || wait_thread.alive?

      wait_thread.value&.exitstatus
    rescue StandardError
      nil
    end
  end
  end
end
