require "test_helper"

module AppSurface
  module Presenters
  end
end

class AppSurface::Presenters::WorkspaceAgentPresenterTest < ActiveSupport::TestCase
  test "emits mount-scoped global instructions" do
    context = create_workspace_context!
    context[:workspace_agent].update!(
      global_instructions: "Use concise Chinese.\n",
      settings_payload: {
        "agent" => {
          "interactive" => {
            "profile_key" => "friendly",
          },
          "subagents" => {
            "default_profile_key" => "researcher",
            "enabled_profile_keys" => ["researcher"],
            "delegation_mode" => "prefer",
          },
        },
      }
    )

    payload = AppSurface::Presenters::WorkspaceAgentPresenter.call(
      workspace_agent: context[:workspace_agent]
    )

    assert_equal context[:workspace_agent].public_id, payload.fetch("workspace_agent_id")
    assert_equal context[:workspace].public_id, payload.fetch("workspace_id")
    assert_equal context[:agent].public_id, payload.fetch("agent_id")
    assert_equal "Use concise Chinese.\n", payload.fetch("global_instructions")
    assert_equal "prefer", payload.dig("settings_payload", "agent", "subagents", "delegation_mode")
    assert_equal "object", payload.dig("settings_schema", "type")
    assert_equal "pragmatic", payload.dig("default_settings_payload", "agent", "interactive", "profile_key")
    refute_includes payload.to_json, %("#{context[:workspace_agent].id}")
  end
end
