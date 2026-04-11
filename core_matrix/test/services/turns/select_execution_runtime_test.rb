require "test_helper"

class Turns::SelectExecutionRuntimeTest < ActiveSupport::TestCase
  test "returns nil when no execution runtime is selected anywhere" do
    installation = create_installation!
    agent = create_agent!(installation: installation, default_execution_runtime: nil)
    user = create_user!(installation: installation)
    binding = create_user_agent_binding!(installation: installation, user: user, agent: agent)
    workspace = create_workspace!(
      installation: installation,
      user: user,
      user_agent_binding: binding,
      default_execution_runtime: nil
    )
    conversation = Conversations::CreateRoot.call(workspace: workspace)

    assert_nil Turns::SelectExecutionRuntime.call(conversation: conversation)
  end

  test "prefers the workspace default execution runtime over the agent default" do
    installation = create_installation!
    agent_default_runtime = create_execution_runtime!(installation: installation, display_name: "Agent Default")
    workspace_default_runtime = create_execution_runtime!(installation: installation, display_name: "Workspace Default")
    create_execution_runtime_connection!(installation: installation, execution_runtime: agent_default_runtime)
    create_execution_runtime_connection!(installation: installation, execution_runtime: workspace_default_runtime)
    agent = create_agent!(installation: installation, default_execution_runtime: agent_default_runtime)
    user = create_user!(installation: installation)
    binding = create_user_agent_binding!(installation: installation, user: user, agent: agent)
    workspace = create_workspace!(
      installation: installation,
      user: user,
      user_agent_binding: binding,
      default_execution_runtime: workspace_default_runtime
    )
    conversation = Conversations::CreateRoot.call(workspace: workspace)

    assert_equal workspace_default_runtime, Turns::SelectExecutionRuntime.call(conversation: conversation)
  end

  test "prefers the previous turn execution runtime over the workspace default" do
    installation = create_installation!
    previous_turn_runtime = create_execution_runtime!(installation: installation, display_name: "Previous Turn")
    workspace_default_runtime = create_execution_runtime!(installation: installation, display_name: "Workspace Default")
    create_execution_runtime_connection!(installation: installation, execution_runtime: previous_turn_runtime)
    create_execution_runtime_connection!(installation: installation, execution_runtime: workspace_default_runtime)
    agent = create_agent!(installation: installation, default_execution_runtime: nil)
    user = create_user!(installation: installation)
    binding = create_user_agent_binding!(installation: installation, user: user, agent: agent)
    workspace = create_workspace!(
      installation: installation,
      user: user,
      user_agent_binding: binding,
      default_execution_runtime: workspace_default_runtime
    )
    conversation = Conversations::CreateRoot.call(workspace: workspace)
    agent_snapshot = create_agent_snapshot!(installation: installation, agent: agent)

    Turn.create!(
      installation: installation,
      conversation: conversation,
      agent_snapshot: agent_snapshot,
      execution_runtime: previous_turn_runtime,
      sequence: 1,
      lifecycle_state: "completed",
      origin_kind: "manual_user",
      origin_payload: {},
      source_ref_type: "User",
      source_ref_id: user.public_id,
      pinned_agent_snapshot_fingerprint: agent_snapshot.fingerprint,
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    assert_equal previous_turn_runtime, Turns::SelectExecutionRuntime.call(conversation: conversation)
  end
end
