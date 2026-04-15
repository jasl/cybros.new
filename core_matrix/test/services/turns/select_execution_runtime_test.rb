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
    current_epoch = initialize_current_execution_epoch!(conversation)
    agent_definition_version = create_agent_definition_version!(installation: installation, agent: agent)
    agent_config_state = AgentConfigStates::Reconcile.call(
      agent: agent,
      agent_definition_version: agent_definition_version
    )
    historical_epoch = ConversationExecutionEpoch.create!(
      installation: installation,
      conversation: conversation,
      execution_runtime: previous_turn_runtime,
      source_execution_epoch: current_epoch,
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

  test "uses the conversation workspace agent default runtime when the current runtime cache is empty" do
    installation = create_installation!
    user = create_user!(installation: installation)
    primary_runtime = create_execution_runtime!(installation: installation, display_name: "Primary Mount Runtime")
    mounted_runtime = create_execution_runtime!(installation: installation, display_name: "Mounted Runtime")
    create_execution_runtime_connection!(installation: installation, execution_runtime: primary_runtime)
    create_execution_runtime_connection!(installation: installation, execution_runtime: mounted_runtime)

    primary_agent = create_agent!(installation: installation, default_execution_runtime: primary_runtime)
    mounted_agent = create_agent!(installation: installation, default_execution_runtime: nil)
    workspace = create_workspace!(installation: installation, user: user, name: "Runtime Selection Workspace")
    create_workspace_agent!(
      installation: installation,
      workspace: workspace,
      agent: primary_agent,
      default_execution_runtime: primary_runtime
    )
    mounted_workspace_agent = create_workspace_agent!(
      installation: installation,
      workspace: workspace,
      agent: mounted_agent,
      default_execution_runtime: mounted_runtime
    )
    conversation = Conversations::CreateRoot.call(workspace_agent: mounted_workspace_agent)

    conversation.update_columns(current_execution_runtime_id: nil)

    assert_equal mounted_runtime, Turns::SelectExecutionRuntime.call(conversation: conversation.reload)
  end

  test "falls back to the conversation agent default runtime when the mount has no runtime" do
    installation = create_installation!
    user = create_user!(installation: installation)
    primary_runtime = create_execution_runtime!(installation: installation, display_name: "Primary Mount Runtime")
    agent_default_runtime = create_execution_runtime!(installation: installation, display_name: "Mounted Agent Default")
    create_execution_runtime_connection!(installation: installation, execution_runtime: primary_runtime)
    create_execution_runtime_connection!(installation: installation, execution_runtime: agent_default_runtime)

    primary_agent = create_agent!(installation: installation, default_execution_runtime: primary_runtime)
    mounted_agent = create_agent!(installation: installation, default_execution_runtime: agent_default_runtime)
    workspace = create_workspace!(installation: installation, user: user, name: "Agent Runtime Fallback Workspace")
    create_workspace_agent!(
      installation: installation,
      workspace: workspace,
      agent: primary_agent,
      default_execution_runtime: primary_runtime
    )
    mounted_workspace_agent = create_workspace_agent!(
      installation: installation,
      workspace: workspace,
      agent: mounted_agent,
      default_execution_runtime: nil
    )
    conversation = Conversations::CreateRoot.call(workspace_agent: mounted_workspace_agent)

    conversation.update_columns(current_execution_runtime_id: nil)

    assert_equal agent_default_runtime, Turns::SelectExecutionRuntime.call(conversation: conversation.reload)
  end
end
