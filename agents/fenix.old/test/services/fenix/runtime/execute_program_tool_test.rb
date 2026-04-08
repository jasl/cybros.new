require "test_helper"

class Fenix::Runtime::ExecuteProgramToolTest < ActiveSupport::TestCase
  test "builds program tool execution context from the shared payload context" do
    payload = runtime_assignment_payload.fetch("payload").merge(
      "program_tool_call" => {
        "call_id" => "tool-call-1",
        "tool_name" => "calculator",
        "arguments" => { "expression" => "2 + 2" },
      }
    )
    captured_context = nil
    executor_class = Fenix::Runtime::ProgramToolExecutor
    original_new = executor_class.method(:new)
    fake_executor = Struct.new(:context) do
      def call(tool_call:, tool_invocation:, command_run:, process_run:)
        Fenix::Runtime::ProgramToolExecutor::Result.new(
          tool_call: tool_call,
          tool_result: 4,
          output_chunks: []
        )
      end
    end

    executor_class.define_singleton_method(:new) do |context:, **kwargs|
      captured_context = context.deep_stringify_keys
      fake_executor.new(context)
    end

    Fenix::Runtime::ExecuteProgramTool.call(payload:)

    assert_equal Fenix::Runtime::PayloadContext.call(payload:), captured_context
  ensure
    executor_class.define_singleton_method(:new, original_new) if executor_class && original_new
  end

  test "supports program tool request payloads that do not include a conversation projection" do
    payload = shared_contract_fixture("core_matrix_fenix_execute_program_tool_mailbox_item").fetch("payload")

    result = Fenix::Runtime::ExecuteProgramTool.call(payload:)

    assert_equal "ok", result.fetch("status")
    assert_equal 4, result.fetch("result")
  end
end
