require "test_helper"

class Fenix::Agent::Prompts::AssemblerTest < ActiveSupport::TestCase
  test "builds a system prompt with all expected sections" do
    assembled = Fenix::Agent::Prompts::Assembler.call(
      profile: "main",
      is_subagent: false,
      workspace_instructions: "Stay in the active workspace.",
      skill_overlay: ["Use the deploy skill."],
      durable_state: {
        "goal" => "Ship the feature",
      },
      execution_context: {
        "memory" => "Memory loaded",
      }
    )

    prompt = assembled.fetch("system_prompt")

    assert_includes prompt, "## Code-Owned Base"
    assert_includes prompt, "## Role Overlay"
    assert_includes prompt, "## Workspace Instructions"
    assert_includes prompt, "## Skill Overlay"
    assert_includes prompt, "## CoreMatrix Durable State"
    assert_includes prompt, "## Execution-Local Fenix Context"
  end
end
