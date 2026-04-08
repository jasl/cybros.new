require "test_helper"

class Fenix::Prompts::AssemblerTest < ActiveSupport::TestCase
  test "assembles the prompt layers in the approved order for the main profile" do
    assembled = Fenix::Prompts::Assembler.call(
      profile: "main",
      is_subagent: false,
      workspace_instructions: "Keep changes scoped to agents/fenix.",
      skill_overlay: ["Skill overlay: use test-driven development when adding behavior."],
      durable_state: {
        "plan_status" => "in_progress",
        "active_goal" => "Ship the 2048 capstone",
      },
      execution_context: {
        "memory" => "No conversation memory loaded.",
        "runtime" => {
          "logical_work_id" => "prepare-round:workflow-node-1",
        },
      }
    )

    system_prompt = assembled.fetch("system_prompt")

    assert system_prompt.index("## Code-Owned Base") < system_prompt.index("## Role Overlay")
    assert system_prompt.index("## Role Overlay") < system_prompt.index("## Workspace Instructions")
    assert system_prompt.index("## Workspace Instructions") < system_prompt.index("## Skill Overlay")
    assert system_prompt.index("## Skill Overlay") < system_prompt.index("## CoreMatrix Durable State")
    assert system_prompt.index("## CoreMatrix Durable State") < system_prompt.index("## Execution-Local Fenix Context")
    assert_includes system_prompt, "You are Fenix."
    assert_includes system_prompt, "Serve the active user"
    assert_includes system_prompt, "Keep changes scoped to agents/fenix."
    assert_includes system_prompt, "Skill overlay: use test-driven development"
    assert_includes system_prompt, "\"plan_status\": \"in_progress\""
    assert_includes system_prompt, "\"logical_work_id\": \"prepare-round:workflow-node-1\""
  end

  test "uses the worker overlay for subagent executions" do
    assembled = Fenix::Prompts::Assembler.call(
      profile: "researcher",
      is_subagent: true,
      workspace_instructions: nil,
      skill_overlay: [],
      durable_state: nil,
      execution_context: {}
    )

    system_prompt = assembled.fetch("system_prompt")

    assert_includes system_prompt, "You are a delegated Fenix worker."
    refute_includes system_prompt, "Serve the active user"
    assert_includes system_prompt, "No workspace instructions provided."
    assert_includes system_prompt, "No active skills loaded."
    assert_includes system_prompt, "No durable state view provided by CoreMatrix."
  end
end
