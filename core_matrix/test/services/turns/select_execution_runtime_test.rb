require "test_helper"

class Turns::SelectExecutionRuntimeTest < ActiveSupport::TestCase
  test "returns nil when no execution runtime is selected anywhere" do
    installation = create_installation!
    agent = create_agent!(installation: installation, default_execution_runtime: nil)
    user = create_user!(installation: installation)
    workspace = create_workspace!(
      installation: installation,
      user: user,
      agent: agent,
      default_execution_runtime: nil
    )
    conversation = Conversations::CreateRoot.call(workspace: workspace)

    assert_nil Turns::SelectExecutionRuntime.call(conversation: conversation)
  end

  test "uses the conversation current execution runtime when present" do
    installation = create_installation!
    agent_default_runtime = create_execution_runtime!(installation: installation, display_name: "Agent Default")
    workspace_default_runtime = create_execution_runtime!(installation: installation, display_name: "Workspace Default")
    create_execution_runtime_connection!(installation: installation, execution_runtime: agent_default_runtime)
    create_execution_runtime_connection!(installation: installation, execution_runtime: workspace_default_runtime)
    agent = create_agent!(installation: installation, default_execution_runtime: agent_default_runtime)
    user = create_user!(installation: installation)
    workspace = create_workspace!(
      installation: installation,
      user: user,
      agent: agent,
      default_execution_runtime: workspace_default_runtime
    )
    conversation = Conversations::CreateRoot.call(workspace: workspace)

    assert_equal workspace_default_runtime, Turns::SelectExecutionRuntime.call(conversation: conversation)
  end

  test "does not infer continuity from the previous turn runtime anymore" do
    installation = create_installation!
    previous_turn_runtime = create_execution_runtime!(installation: installation, display_name: "Previous Turn")
    workspace_default_runtime = create_execution_runtime!(installation: installation, display_name: "Workspace Default")
    previous_turn_runtime_connection = create_execution_runtime_connection!(installation: installation, execution_runtime: previous_turn_runtime)
    create_execution_runtime_connection!(installation: installation, execution_runtime: workspace_default_runtime)
    agent = create_agent!(installation: installation, default_execution_runtime: nil)
    user = create_user!(installation: installation)
    workspace = create_workspace!(
      installation: installation,
      user: user,
      agent: agent,
      default_execution_runtime: workspace_default_runtime
    )
    conversation = Conversations::CreateRoot.call(workspace: workspace)
    agent_definition_version = create_agent_definition_version!(installation: installation, agent: agent)
    agent_config_state = AgentConfigStates::Reconcile.call(
      agent: agent,
      agent_definition_version: agent_definition_version
    )
    historical_epoch = ConversationExecutionEpoch.create!(
      installation: installation,
      conversation: conversation,
      execution_runtime: previous_turn_runtime,
      source_execution_epoch: conversation.current_execution_epoch,
      sequence: 2,
      lifecycle_state: "superseded",
      continuity_payload: {},
      opened_at: Time.current,
      closed_at: Time.current
    )

    Turn.create!(
      installation: installation,
      conversation: conversation,
      user: conversation.user,
      workspace: conversation.workspace,
      agent: conversation.agent,
      agent_definition_version: agent_definition_version,
      execution_runtime: previous_turn_runtime,
      execution_runtime_version: previous_turn_runtime_connection.execution_runtime_version,
      sequence: 1,
      lifecycle_state: "completed",
      origin_kind: "manual_user",
      origin_payload: {},
      source_ref_type: "User",
      source_ref_id: user.public_id,
      pinned_agent_definition_fingerprint: agent_definition_version.definition_fingerprint,
      agent_config_version: agent_config_state.version,
      agent_config_content_fingerprint: agent_config_state.content_fingerprint,
      execution_epoch: historical_epoch,
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    assert_equal workspace_default_runtime, Turns::SelectExecutionRuntime.call(conversation: conversation)
  end
end
