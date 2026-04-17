require "json"
require "securerandom"
require "time"

module CybrosNexus
  module Mailbox
    class AssignmentExecutor
      InvalidRequestError = Class.new(StandardError)

      COMMAND_TOOL_NAMES = %w[
        exec_command
        write_stdin
        command_run_read_output
        command_run_wait
        command_run_list
        command_run_terminate
      ].freeze
      PROCESS_TOOL_NAMES = %w[
        process_exec
        process_list
        process_proxy_info
        process_read_output
      ].freeze

      def initialize(store:, outbox:, command_host:, process_host:, workdir:, environment: {})
        @store = store
        @outbox = outbox
        @command_host = command_host
        @process_host = process_host
        @workdir = workdir
        @environment = environment
      end

      def call(mailbox_item:)
        @mailbox_item = normalize_hash(mailbox_item)
        persist_attempt(state: "running")
        enqueue_execution_event(
          method_id: "execution_started",
          event_key: "01:execution-started:#{logical_work_id}:#{attempt_no}",
          payload: base_execution_payload("execution_started").merge(
            "expected_duration_seconds" => 30
          )
        )

        terminal_payload = execute_assignment

        enqueue_execution_event(
          method_id: "execution_complete",
          event_key: "03:execution-complete:#{logical_work_id}:#{attempt_no}",
          payload: base_execution_payload("execution_complete").merge(
            "terminal_payload" => terminal_payload
          )
        )
        persist_attempt(state: "completed", terminal_outcome: terminal_payload)

        {
          "status" => "ok",
          "mailbox_item_id" => @mailbox_item.fetch("item_id"),
        }
      rescue StandardError => error
        failure_payload = failure_payload_for(error)
        terminal_payload = terminal_failure_payload(failure_payload)

        enqueue_execution_event(
          method_id: "execution_fail",
          event_key: "02:execution-fail:#{logical_work_id}:#{attempt_no}:#{SecureRandom.uuid}",
          payload: base_execution_payload("execution_fail").merge(
            "terminal_payload" => terminal_payload
          )
        ) if @mailbox_item
        persist_attempt(state: "failed", terminal_outcome: terminal_payload) if @mailbox_item

        {
          "status" => "failed",
          "mailbox_item_id" => @mailbox_item&.fetch("item_id", nil),
          "failure" => failure_payload,
        }.compact
      end

      private

      def execute_assignment
        mode = task_payload.fetch("mode", "deterministic_tool")

        case mode
        when "tool_call"
          execute_tool_call
        when "raise_error"
          raise StandardError, "requested execution assignment failure"
        else
          deterministic_result
        end
      end

      def execute_tool_call
        tool_name = tool_call.fetch("tool_name")
        tool_result = dispatch_tool_call(tool_name)
        output_chunks = output_chunks_for(tool_result)

        unless output_chunks.empty?
          enqueue_execution_event(
            method_id: "execution_progress",
            event_key: "02:execution-progress:#{logical_work_id}:#{attempt_no}:#{SecureRandom.uuid}",
            payload: base_execution_payload("execution_progress").merge(
              "progress_payload" => {
                "tool_invocation_output" => {
                  "tool_invocation_id" => tool_invocation_id,
                  "call_id" => tool_call.fetch("call_id"),
                  "tool_name" => tool_name,
                  "command_run_id" => command_run_id_for(tool_result),
                  "output_chunks" => output_chunks,
                }.compact,
              }
            )
          )
        end

        response_payload = normalize_hash(tool_result).merge(
          "output_streamed" => !output_chunks.empty?
        )

        {
          "tool_invocations" => [
            {
              "event" => "completed",
              "tool_invocation_id" => tool_invocation_id,
              "call_id" => tool_call.fetch("call_id"),
              "tool_name" => tool_name,
              "command_run_id" => command_run_id_for(response_payload),
              "response_payload" => response_payload,
            }.compact,
          ],
          "output" => success_summary_for(tool_name:, result: response_payload),
        }.compact
      end

      def deterministic_result
        if expression
          result = evaluate_expression(expression)
          return {
            "kind" => "calculator",
            "expression" => expression,
            "result" => result,
            "content" => "The calculator returned #{result}.",
            "output" => "The calculator returned #{result}.",
          }
        end

        if echo_text
          return {
            "kind" => "echo",
            "text" => echo_text,
            "content" => "Echo: #{echo_text}",
            "output" => "Echo: #{echo_text}",
          }
        end

        raise InvalidRequestError, "deterministic tool request requires expression or echo_text"
      end

      def evaluate_expression(raw_expression)
        normalized = raw_expression.to_s
        raise InvalidRequestError, "expression contains unsupported characters" unless normalized.match?(/\A[\d\s+\-*\/().]+\z/)

        Kernel.eval(normalized, binding, __FILE__, __LINE__)
      rescue StandardError => error
        raise InvalidRequestError, error.message
      end

      def dispatch_tool_call(tool_name)
        case tool_name
        when *COMMAND_TOOL_NAMES
          command_tools.call(
            tool_name: tool_name,
            arguments: tool_call.fetch("arguments", {}),
            resource_ref: runtime_resource_refs["command_run"]
          )
        when *PROCESS_TOOL_NAMES
          process_tools.call(
            tool_name: tool_name,
            arguments: tool_call.fetch("arguments", {}),
            resource_ref: runtime_resource_refs["process_run"]
          )
        else
          raise InvalidRequestError, "unsupported execution runtime tool #{tool_name}"
        end
      end

      def output_chunks_for(tool_result)
        result = normalize_hash(tool_result)
        chunks = []
        stdout = result["stdout"]
        stdout = result["stdout_tail"] if blank_string?(stdout)
        stderr = result["stderr"]
        stderr = result["stderr_tail"] if blank_string?(stderr)

        chunks << { "stream" => "stdout", "text" => stdout } unless blank_string?(stdout)
        chunks << { "stream" => "stderr", "text" => stderr } unless blank_string?(stderr)
        chunks
      end

      def success_summary_for(tool_name:, result:)
        return "Started the requested process." if tool_name == "process_exec"

        if result["output"].is_a?(String) && !result["output"].empty?
          result["output"]
        else
          "Execution runtime completed the requested tool call."
        end
      end

      def terminal_failure_payload(failure_payload)
        payload = failure_payload.merge(
          "last_error_summary" => failure_payload["message"]
        )

        return payload if tool_call.nil?

        payload.merge(
          "tool_invocations" => [
            {
              "event" => "failed",
              "tool_invocation_id" => tool_invocation_id,
              "call_id" => tool_call.fetch("call_id"),
              "tool_name" => tool_call.fetch("tool_name"),
              "command_run_id" => runtime_resource_refs.dig("command_run", "command_run_id"),
              "error_payload" => failure_payload,
            }.compact,
          ]
        )
      end

      def failure_payload_for(error)
        case error
        when InvalidRequestError
          {
            "classification" => "semantic",
            "code" => "invalid_deterministic_tool_request",
            "message" => error.message,
            "retryable" => false,
          }
        when CybrosNexus::Tools::ExecCommand::ValidationError, CybrosNexus::Tools::ProcessTools::ValidationError
          {
            "classification" => "semantic",
            "code" => "invalid_tool_request",
            "message" => error.message,
            "retryable" => false,
          }
        else
          {
            "classification" => "runtime",
            "code" => "runtime_error",
            "message" => error.message,
            "retryable" => false,
          }
        end
      end

      def command_tools
        @command_tools ||= CybrosNexus::Tools::ExecCommand.new(
          command_host: @command_host,
          runtime_owner_id: runtime_owner_id,
          workdir: @workdir,
          environment: @environment
        )
      end

      def process_tools
        @process_tools ||= CybrosNexus::Tools::ProcessTools.new(
          process_host: @process_host,
          runtime_owner_id: runtime_owner_id,
          workdir: @workdir,
          environment: @environment
        )
      end

      def persist_attempt(state:, terminal_outcome: nil)
        @store.database.execute(
          <<~SQL,
            INSERT INTO execution_attempts (logical_work_id, attempt_no, state, terminal_outcome, updated_at)
            VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(logical_work_id, attempt_no) DO UPDATE SET
              state = excluded.state,
              terminal_outcome = excluded.terminal_outcome,
              updated_at = excluded.updated_at
          SQL
          [
            logical_work_id,
            attempt_no,
            state,
            terminal_outcome ? JSON.generate(terminal_outcome) : nil,
            Time.now.utc.iso8601,
          ]
        )
      end

      def enqueue_execution_event(method_id:, event_key:, payload:)
        @outbox.enqueue(
          event_key: event_key,
          event_type: method_id,
          payload: payload
        )
      end

      def base_execution_payload(method_id)
        {
          "method_id" => method_id,
          "protocol_message_id" => "nexus-#{method_id}-#{SecureRandom.uuid}",
          "control_plane" => @mailbox_item.fetch("control_plane"),
          "mailbox_item_id" => @mailbox_item.fetch("item_id"),
          "agent_task_run_id" => task.fetch("agent_task_run_id"),
          "logical_work_id" => logical_work_id,
          "attempt_no" => attempt_no,
        }.compact
      end

      def logical_work_id
        @mailbox_item.fetch("logical_work_id")
      end

      def attempt_no
        Integer(@mailbox_item.fetch("attempt_no", 1))
      end

      def task
        @task ||= normalize_hash(payload.fetch("task", {}))
      end

      def payload
        @payload ||= normalize_hash(@mailbox_item.fetch("payload"))
      end

      def task_payload
        @task_payload ||= normalize_hash(payload.fetch("task_payload", {}))
      end

      def tool_call
        raw_tool_call = payload["tool_call"]
        return nil if raw_tool_call.nil?

        @tool_call ||= normalize_hash(raw_tool_call)
      end

      def runtime_resource_refs
        @runtime_resource_refs ||= normalize_hash(payload.fetch("runtime_resource_refs", {}))
      end

      def runtime_owner_id
        runtime_resource_refs.dig("command_run", "runtime_owner_id") ||
          runtime_resource_refs.dig("process_run", "runtime_owner_id") ||
          task["workflow_node_id"] ||
          logical_work_id
      end

      def tool_invocation_id
        runtime_resource_refs.dig("tool_invocation", "tool_invocation_id")
      end

      def command_run_id_for(tool_result)
        result = normalize_hash(tool_result)
        result["command_run_id"] || runtime_resource_refs.dig("command_run", "command_run_id")
      end

      def expression
        value = task_payload["expression"]
        blank_string?(value) ? nil : value.to_s
      end

      def echo_text
        value = task_payload["echo_text"] || task_payload["text"]
        blank_string?(value) ? nil : value.to_s
      end

      def normalize_hash(value)
        JSON.parse(JSON.generate(value || {}))
      end

      def blank_string?(value)
        value.nil? || value.to_s.empty?
      end
    end
  end
end
