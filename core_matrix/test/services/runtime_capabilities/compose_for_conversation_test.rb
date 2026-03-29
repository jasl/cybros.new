require "test_helper"

class RuntimeCapabilities::ComposeForConversationTest < ActiveSupport::TestCase
  SUBAGENT_TOOL_NAMES = RuntimeCapabilityContract::RESERVED_SUBAGENT_TOOL_NAMES

  test "conversation attachments stay disabled when the environment does not allow uploads" do
    registration = register_profile_aware_runtime!(
      environment_capability_payload: { "conversation_attachment_upload" => false }
    )
    conversation = create_root_conversation_for!(registration)

    contract = RuntimeCapabilities::ComposeForConversation.call(conversation: conversation)

    assert_equal false, contract.fetch("conversation_attachment_upload")
    assert_includes contract.fetch("tool_catalog").map { |entry| entry.fetch("tool_name") }, "subagent_spawn"
  end

  test "conversation attachments stay enabled when the environment allows uploads" do
    registration = register_profile_aware_runtime!(
      environment_capability_payload: { "conversation_attachment_upload" => true }
    )
    conversation = create_root_conversation_for!(registration)

    contract = RuntimeCapabilities::ComposeForConversation.call(conversation: conversation)

    assert_equal true, contract.fetch("conversation_attachment_upload")
    assert_includes contract.fetch("tool_catalog").map { |entry| entry.fetch("tool_name") }, "subagent_spawn"
  end

  test "conversation tool catalog prefers environment tools over agent tools with the same name" do
    registration = register_profile_aware_runtime!(
      environment_tool_catalog: [
        {
          "tool_name" => "shell_exec",
          "tool_kind" => "environment_runtime",
          "implementation_source" => "execution_environment",
          "implementation_ref" => "env/shell_exec",
          "input_schema" => { "type" => "object", "properties" => {} },
          "result_schema" => { "type" => "object", "properties" => {} },
          "streaming_support" => false,
          "idempotency_policy" => "best_effort",
        },
      ],
      tool_catalog: [
        {
          "tool_name" => "shell_exec",
          "tool_kind" => "agent_observation",
          "implementation_source" => "agent",
          "implementation_ref" => "agent/shell_exec",
          "input_schema" => { "type" => "object", "properties" => {} },
          "result_schema" => { "type" => "object", "properties" => {} },
          "streaming_support" => false,
          "idempotency_policy" => "best_effort",
        },
      ]
    )
    conversation = create_root_conversation_for!(registration)

    contract = RuntimeCapabilities::ComposeForConversation.call(conversation: conversation)
    shell_entry = contract.fetch("tool_catalog").find { |entry| entry.fetch("tool_name") == "shell_exec" }

    assert_equal "environment_runtime", shell_entry.fetch("tool_kind")
  end

  test "subagents.enabled false hides the whole subagent tool family" do
    registration = register_profile_aware_runtime!
    conversation = create_root_conversation_for!(registration)

    Conversations::UpdateOverride.call(
      conversation: conversation,
      payload: { "subagents" => { "enabled" => false } },
      schema_fingerprint: "schema-v1",
      selector_mode: "auto"
    )

    contract = RuntimeCapabilities::ComposeForConversation.call(conversation: conversation)

    assert_empty contract.fetch("tool_catalog").select { |entry| SUBAGENT_TOOL_NAMES.include?(entry.fetch("tool_name")) }
  end

  test "allow_nested false hides subagent_spawn for child conversations" do
    registration = register_profile_aware_runtime!(
      default_config_snapshot: profile_aware_default_config_snapshot.deep_merge(
        "subagents" => { "allow_nested" => false }
      )
    )
    root_conversation = create_root_conversation_for!(registration)
    child = create_subagent_conversation_chain!(
      registration: registration,
      parent_conversation: root_conversation,
      depth: 0,
      profile_key: "researcher"
    ).fetch(:conversation)

    root_tool_names = RuntimeCapabilities::ComposeForConversation.call(
      conversation: root_conversation
    ).fetch("tool_catalog").map { |entry| entry.fetch("tool_name") }
    child_tool_names = RuntimeCapabilities::ComposeForConversation.call(
      conversation: child
    ).fetch("tool_catalog").map { |entry| entry.fetch("tool_name") }

    assert_includes root_tool_names, "subagent_spawn"
    refute_includes child_tool_names, "subagent_spawn"
    assert_includes child_tool_names, "subagent_send"
  end

  test "depth at max depth hides subagent_spawn while keeping other subagent tools visible" do
    registration = register_profile_aware_runtime!(
      default_config_snapshot: profile_aware_default_config_snapshot.deep_merge(
        "subagents" => { "max_depth" => 1 }
      )
    )
    child = create_subagent_conversation_chain!(
      registration: registration,
      parent_conversation: create_root_conversation_for!(registration),
      depth: 1,
      profile_key: "researcher"
    ).fetch(:conversation)

    child_tool_names = RuntimeCapabilities::ComposeForConversation.call(
      conversation: child
    ).fetch("tool_catalog").map { |entry| entry.fetch("tool_name") }

    refute_includes child_tool_names, "subagent_spawn"
    assert_includes child_tool_names, "subagent_wait"
    assert_includes child_tool_names, "subagent_close"
  end

  test "visible child tools stay a subset of visible parent tools after profile masking" do
    registration = register_profile_aware_runtime!(
      profile_catalog: profile_catalog_with_allowed_tool_names(
        main_tool_names: %w[shell_exec compact_context] + SUBAGENT_TOOL_NAMES,
        researcher_tool_names: %w[shell_exec subagent_send subagent_wait subagent_close subagent_list]
      ),
      tool_catalog: default_tool_catalog("shell_exec", "compact_context")
    )
    root_conversation = create_root_conversation_for!(registration)
    child = create_subagent_conversation_chain!(
      registration: registration,
      parent_conversation: root_conversation,
      depth: 0,
      profile_key: "researcher"
    ).fetch(:conversation)

    parent_tool_names = RuntimeCapabilities::ComposeForConversation.call(
      conversation: root_conversation
    ).fetch("tool_catalog").map { |entry| entry.fetch("tool_name") }
    child_tool_names = RuntimeCapabilities::ComposeForConversation.call(
      conversation: child
    ).fetch("tool_catalog").map { |entry| entry.fetch("tool_name") }

    assert_equal [], child_tool_names - parent_tool_names
    refute_includes child_tool_names, "compact_context"
    refute_includes child_tool_names, "subagent_spawn"
  end

  test "masked tools reject direct invocation even when the caller guesses the tool name" do
    registration = register_profile_aware_runtime!(
      profile_catalog: profile_catalog_with_allowed_tool_names(
        main_tool_names: %w[shell_exec compact_context] + SUBAGENT_TOOL_NAMES,
        researcher_tool_names: %w[shell_exec subagent_send subagent_wait subagent_close subagent_list]
      ),
      tool_catalog: default_tool_catalog("shell_exec", "compact_context")
    )
    child = create_subagent_conversation_chain!(
      registration: registration,
      parent_conversation: create_root_conversation_for!(registration),
      depth: 0,
      profile_key: "researcher"
    ).fetch(:conversation)

    error = assert_raises(RuntimeCapabilities::ComposeForConversation::ToolNotVisibleError) do
      RuntimeCapabilities::ComposeForConversation.visible_tool_entry!(
        conversation: child,
        tool_name: "subagent_spawn"
      )
    end

    assert_includes error.message, "subagent_spawn"
  end

  test "conversation overrides reject interactive profile mutations" do
    registration = register_profile_aware_runtime!
    conversation = create_root_conversation_for!(registration)

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Conversations::UpdateOverride.call(
        conversation: conversation,
        payload: { "interactive" => { "profile" => "researcher" } },
        schema_fingerprint: "schema-v1",
        selector_mode: "auto"
      )
    end

    assert_includes error.record.errors[:override_payload], "must only contain mutable subagent policy keys"
  end

  private

  def register_profile_aware_runtime!(environment_capability_payload: {}, environment_tool_catalog: [], tool_catalog: default_tool_catalog("shell_exec"), profile_catalog: default_profile_catalog, default_config_snapshot: profile_aware_default_config_snapshot)
    register_agent_runtime!(
      environment_capability_payload: environment_capability_payload,
      environment_tool_catalog: environment_tool_catalog,
      tool_catalog: tool_catalog,
      profile_catalog: profile_catalog,
      config_schema_snapshot: profile_aware_config_schema_snapshot,
      conversation_override_schema_snapshot: subagent_policy_override_schema_snapshot,
      default_config_snapshot: default_config_snapshot
    )
  end

  def create_root_conversation_for!(registration)
    workspace = create_workspace!(
      installation: registration[:installation],
      user: registration[:actor],
      user_agent_binding: create_user_agent_binding!(
        installation: registration[:installation],
        user: registration[:actor],
        agent_installation: registration[:agent_installation]
      )
    )

    Conversations::CreateRoot.call(
      workspace: workspace,
      execution_environment: registration[:execution_environment],
      agent_deployment: registration[:deployment]
    )
  end

  def create_subagent_conversation_chain!(registration:, parent_conversation:, depth:, profile_key:)
    previous_conversation = parent_conversation
    previous_session = nil

    (depth + 1).times do |index|
      conversation = create_conversation_record!(
        installation: registration[:installation],
        workspace: parent_conversation.workspace,
        parent_conversation: previous_conversation,
        kind: "fork",
        execution_environment: registration[:execution_environment],
        agent_deployment: registration[:deployment],
        addressability: "agent_addressable"
      )
      session = SubagentSession.create!(
        installation: registration[:installation],
        conversation: conversation,
        owner_conversation: previous_conversation,
        parent_subagent_session: previous_session,
        scope: "conversation",
        profile_key: profile_key,
        depth: index
      )

      previous_conversation = conversation
      previous_session = session
    end

    {
      conversation: previous_conversation,
      subagent_session: previous_session,
    }
  end

  def profile_catalog_with_allowed_tool_names(main_tool_names:, researcher_tool_names:)
    default_profile_catalog.deep_merge(
      "main" => { "allowed_tool_names" => main_tool_names },
      "researcher" => { "allowed_tool_names" => researcher_tool_names }
    )
  end
end
