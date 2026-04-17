require "open3"
require "securerandom"

module CybrosNexus
  module Resources
    class ProcessHost
      ValidationError = Class.new(StandardError)

      READ_CHUNK_SIZE = 4_096

      def initialize(store:, registry:, outbox:)
        @store = store
        @registry = registry
        @outbox = outbox
      end

      def start(process_run_id:, runtime_owner_id:, command_line:, workdir:, environment: {}, proxy_port: nil)
        stdin, output, wait_thread = Open3.popen2e(
          environment,
          "/bin/sh",
          "-lc",
          command_line.to_s,
          chdir: workdir,
          pgroup: true
        )
        stdin.close

        handle = ProcessRegistry::Handle.new(
          process_run_id: process_run_id,
          runtime_owner_id: runtime_owner_id,
          stdin: stdin,
          output: output,
          wait_thread: wait_thread,
          pid: wait_thread.pid,
          proxy_path: proxy_path_for(process_run_id, proxy_port),
          proxy_target_url: proxy_target_url_for(proxy_port),
          lifecycle_state: "running",
          exit_status: nil,
          stdout_bytes: 0,
          stdout_tail: +""
        )
        @registry.register(handle)

        enqueue_event(
          event_key: "process-started:#{process_run_id}",
          event_type: "process_started",
          payload: {
            "method_id" => "process_started",
            "protocol_message_id" => "nexus-process-started-#{SecureRandom.uuid}",
            "resource_type" => "ProcessRun",
            "resource_id" => process_run_id,
          }
        )

        handle.output_thread = start_output_thread(handle)
        handle.watcher_thread = start_watcher_thread(handle)

        {
          "process_run_id" => process_run_id,
          "lifecycle_state" => "running",
          "proxy_path" => handle.proxy_path,
          "proxy_target_url" => handle.proxy_target_url,
        }.compact
      end

      def list(runtime_owner_id:)
        @registry.list(runtime_owner_id:)
      end

      def read_output(process_run_id:, runtime_owner_id:)
        snapshot = lookup_owned_snapshot!(process_run_id:, runtime_owner_id:)
        snapshot
      end

      def proxy_info(process_run_id:)
        snapshot = @registry.snapshot(process_run_id:)
        return nil if snapshot.nil?

        {
          "process_run_id" => process_run_id,
          "proxy_path" => snapshot["proxy_path"],
          "proxy_target_url" => snapshot["proxy_target_url"],
        }
      end

      def shutdown
        @registry.shutdown.each do |handle|
          terminate_process_tree!(handle.pid, signal: "TERM")
          sleep(0.05)
          terminate_process_tree!(handle.pid, signal: "KILL") if handle.wait_thread.alive?
          handle.output.close unless handle.output.closed?
          handle.wait_thread.join(0.5)
          handle.output_thread&.join(0.5)
          handle.watcher_thread&.join(0.5)
          @registry.release(process_run_id: handle.process_run_id)
        end
      end

      private

      def start_output_thread(handle)
        Thread.new do
          Thread.current.report_on_exception = false

          loop do
            chunk = handle.output.readpartial(READ_CHUNK_SIZE)
            next if chunk.empty?

            @registry.append_output(process_run_id: handle.process_run_id, text: chunk)
            enqueue_event(
              event_key: "process-output:#{handle.process_run_id}:#{SecureRandom.uuid}",
              event_type: "process_output",
              payload: {
                "method_id" => "process_output",
                "protocol_message_id" => "nexus-process-output-#{SecureRandom.uuid}",
                "resource_type" => "ProcessRun",
                "resource_id" => handle.process_run_id,
                "output_chunks" => [
                  {
                    "stream" => "stdout",
                    "text" => chunk,
                  },
                ],
              }
            )
          end
        rescue EOFError, IOError
          nil
        end
      end

      def start_watcher_thread(handle)
        Thread.new do
          Thread.current.report_on_exception = false

          status = handle.wait_thread.value
          handle.output_thread&.join(0.5)
          snapshot = @registry.transition(
            process_run_id: handle.process_run_id,
            lifecycle_state: status.exitstatus.to_i.zero? ? "stopped" : "failed",
            exit_status: status.exitstatus
          )
          next if snapshot.nil?

          enqueue_event(
            event_key: "process-exited:#{handle.process_run_id}",
            event_type: "process_exited",
            payload: {
              "method_id" => "process_exited",
              "protocol_message_id" => "nexus-process-exited-#{SecureRandom.uuid}",
              "resource_type" => "ProcessRun",
              "resource_id" => handle.process_run_id,
              "lifecycle_state" => snapshot.fetch("lifecycle_state"),
              "exit_status" => snapshot.fetch("exit_status"),
            }
          )

          @registry.release(process_run_id: handle.process_run_id)
        rescue IOError, Errno::ECHILD
          nil
        end
      end

      def lookup_owned_snapshot!(process_run_id:, runtime_owner_id:)
        snapshot = @registry.snapshot(process_run_id:)
        raise ValidationError, "unknown process run #{process_run_id}" if snapshot.nil?
        raise ValidationError, "process run #{process_run_id} is not owned by this execution" if snapshot.fetch("runtime_owner_id") != runtime_owner_id

        snapshot
      end

      def proxy_path_for(process_run_id, proxy_port)
        return nil unless proxy_port

        "/processes/#{process_run_id}"
      end

      def proxy_target_url_for(proxy_port)
        return nil unless proxy_port

        "http://127.0.0.1:#{proxy_port}"
      end

      def enqueue_event(event_key:, event_type:, payload:)
        @outbox.enqueue(
          event_key: event_key,
          event_type: event_type,
          payload: payload
        )
      end

      def terminate_process_tree!(pid, signal:)
        [(-pid.to_i), pid.to_i].each do |target|
          Process.kill(signal, target)
          return
        rescue Errno::ESRCH
          next
        end
      rescue Errno::EPERM
        nil
      end
    end
  end
end
