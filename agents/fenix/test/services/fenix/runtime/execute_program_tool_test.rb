require "test_helper"

class Fenix::Runtime::ExecuteProgramToolTest < ActiveSupport::TestCase
  test "executes the shared calculator contract fixture" do
    fixture_payload = JSON.parse(
      File.read(
        Rails.root.join("..", "..", "shared", "fixtures", "contracts", "core_matrix_fenix_execute_program_tool_mailbox_item.json")
      )
    ).fetch("payload")

    response = Fenix::Runtime::ExecuteProgramTool.call(payload: fixture_payload)

    assert_equal "ok", response.fetch("status")
    assert_equal "calculator", response.dig("program_tool_call", "tool_name")
    assert_equal({ "value" => 4 }, response.fetch("result"))
    assert_equal [], response.fetch("output_chunks")
    assert_equal [], response.fetch("summary_artifacts")
  end
end
