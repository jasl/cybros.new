require "test_helper"

class Runtime::Assignments::DispatchModeTest < ActiveSupport::TestCase
  test "defaults to deterministic tool mode when no specialized handler matches" do
    dispatch = Runtime::Assignments::DispatchMode.call(
      task_payload: {},
      runtime_context: {}
    )

    assert_equal "deterministic_tool", dispatch.fetch("kind")
  end

  test "returns an explicit unsupported result for legacy skill flow modes" do
    dispatch = Runtime::Assignments::DispatchMode.call(
      task_payload: { "mode" => "skills_load", "skill_name" => "portable-notes" },
      runtime_context: {}
    )

    assert_equal "unsupported_skill_flow", dispatch.fetch("kind")
    assert_equal "skills_load", dispatch.fetch("mode")
  end
end
