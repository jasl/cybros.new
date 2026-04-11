require "test_helper"

class Nexus::Runtime::Assignments::DeterministicToolTest < ActiveSupport::TestCase
  test "evaluates arithmetic expressions across the supported operators" do
    assert_equal(
      {
        "kind" => "calculator",
        "expression" => "7 + 5",
        "result" => 12,
        "content" => "The calculator returned 12.",
      },
      Nexus::Runtime::Assignments::DeterministicTool.call(task_payload: { "expression" => "7 + 5" })
    )
    assert_equal 8, Nexus::Runtime::Assignments::DeterministicTool.call(task_payload: { "expression" => "11 - 3" }).fetch("result")
    assert_equal 36, Nexus::Runtime::Assignments::DeterministicTool.call(task_payload: { "expression" => "9 * 4" }).fetch("result")
    assert_equal 12, Nexus::Runtime::Assignments::DeterministicTool.call(task_payload: { "expression" => "144 / 12" }).fetch("result")
  end

  test "returns echo payloads when echo text is provided" do
    assert_equal(
      {
        "kind" => "echo",
        "text" => "hello runtime",
        "content" => "Echo: hello runtime",
      },
      Nexus::Runtime::Assignments::DeterministicTool.call(task_payload: { "echo_text" => "hello runtime" })
    )
  end

  test "raises a deterministic request error for unsupported expressions" do
    error = assert_raises(Nexus::Runtime::Assignments::DeterministicTool::InvalidRequestError) do
      Nexus::Runtime::Assignments::DeterministicTool.call(task_payload: { "expression" => "7 ^ 5" })
    end

    assert_match(/unsupported arithmetic operator/, error.message)
  end
end
