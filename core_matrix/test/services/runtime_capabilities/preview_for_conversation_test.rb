require "test_helper"

class RuntimeCapabilities::PreviewForConversationTest < ActiveSupport::TestCase
  SUBAGENT_TOOL_NAMES = RuntimeCapabilityContract::RESERVED_SUBAGENT_TOOL_NAMES

  test "preview contracts omit the removed attachment-access helper from the top-level payload" do
    registration = register_profile_aware_runtime!(
      execution_runtime_capability_payload: { "attachment_access" => { "request_attachment" => true } }
    )
    conversation = create_root_conversation_for!(registration)

    contract = RuntimeCapabilities::PreviewForConversation.call(conversation: conversation)

    refute contract.key?("attachment_access")
    assert_includes contract.fetch("tool_catalog").map { |entry| entry.fetch("tool_name") }, "subagent_spawn"
  end

  test "preview contracts still include the selected execution runtime when available" do
    registration = register_profile_aware_runtime!(
      execution_runtime_capability_payload: { "attachment_access" => { "request_attachment" => true } }
    )
    conversation = create_root_conversation_for!(registration)

    contract = RuntimeCapabilities::PreviewForConversation.call(conversation: conversation)

    assert_equal registration[:execution_runtime].public_id, contract.fetch("execution_runtime_id")
    assert_includes contract.fetch("tool_catalog").map { |entry| entry.fetch("tool_name") }, "subagent_spawn"
  end

  test "conversation tool catalog prefers environment tools over agent tools with the same name" do
    registration = register_profile_aware_runtime!(
      execution_runtime_tool_catalog: [
        {
          "tool_name" => "exec_command",
          "tool_kind" => "execution_runtime",
          "implementation_source" => "execution_runtime",
          "implementation_ref" => "env/exec_command",
          "input_schema" => { "type" => "object", "properties" => {} },
          "result_schema" => { "type" => "object", "properties" => {} },
          "streaming_support" => false,
          "idempotency_policy" => "best_effort",
        },
      ],
      tool_catalog: [
        {
          "tool_name" => "exec_command",
          "tool_kind" => "agent_observation",
          "implementation_source" => "agent",
          "implementation_ref" => "agent/exec_command",
          "input_schema" => { "type" => "object", "properties" => {} },
          "result_schema" => { "type" => "object", "properties" => {} },
          "streaming_support" => false,
          "idempotency_policy" => "best_effort",
        },
      ]
    )
    conversation = create_root_conversation_for!(registration)

    contract = RuntimeCapabilities::PreviewForConversation.call(conversation: conversation)
    shell_entry = contract.fetch("tool_catalog").find { |entry| entry.fetch("tool_name") == "exec_command" }

    assert_equal "execution_runtime", shell_entry.fetch("tool_kind")
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

    contract = RuntimeCapabilities::PreviewForConversation.call(conversation: conversation)

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

    root_tool_names = RuntimeCapabilities::PreviewForConversation.call(
      conversation: root_conversation
    ).fetch("tool_catalog").map { |entry| entry.fetch("tool_name") }
    child_tool_names = RuntimeCapabilities::PreviewForConversation.call(
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

    child_tool_names = RuntimeCapabilities::PreviewForConversation.call(
      conversation: child
    ).fetch("tool_catalog").map { |entry| entry.fetch("tool_name") }

    refute_includes child_tool_names, "subagent_spawn"
    assert_includes child_tool_names, "subagent_wait"
    assert_includes child_tool_names, "subagent_close"
  end

  test "visible child tools stay a subset of visible parent tools after profile masking" do
    registration = register_profile_aware_runtime!(
      profile_catalog: profile_catalog_with_allowed_tool_names(
        main_tool_names: %w[exec_command compact_context] + SUBAGENT_TOOL_NAMES,
        researcher_tool_names: %w[exec_command subagent_send subagent_wait subagent_close subagent_list]
      ),
      tool_catalog: default_tool_catalog("exec_command", "compact_context")
    )
    root_conversation = create_root_conversation_for!(registration)
    child = create_subagent_conversation_chain!(
      registration: registration,
      parent_conversation: root_conversation,
      depth: 0,
      profile_key: "researcher"
    ).fetch(:conversation)

    parent_tool_names = RuntimeCapabilities::PreviewForConversation.call(
      conversation: root_conversation
    ).fetch("tool_catalog").map { |entry| entry.fetch("tool_name") }
    child_tool_names = RuntimeCapabilities::PreviewForConversation.call(
      conversation: child
    ).fetch("tool_catalog").map { |entry| entry.fetch("tool_name") }

    assert_equal [], child_tool_names - parent_tool_names
    refute_includes child_tool_names, "compact_context"
    refute_includes child_tool_names, "subagent_spawn"
  end

  test "masked tools reject direct invocation even when the caller guesses the tool name" do
    registration = register_profile_aware_runtime!(
      profile_catalog: profile_catalog_with_allowed_tool_names(
        main_tool_names: %w[exec_command compact_context] + SUBAGENT_TOOL_NAMES,
        researcher_tool_names: %w[exec_command subagent_send subagent_wait subagent_close subagent_list]
      ),
      tool_catalog: default_tool_catalog("exec_command", "compact_context")
    )
    child = create_subagent_conversation_chain!(
      registration: registration,
      parent_conversation: create_root_conversation_for!(registration),
      depth: 0,
      profile_key: "researcher"
    ).fetch(:conversation)

    error = assert_raises(RuntimeCapabilities::PreviewForConversation::ToolNotVisibleError) do
      RuntimeCapabilities::PreviewForConversation.visible_tool_entry!(
        conversation: child,
        tool_name: "subagent_spawn"
      )
    end

    assert_includes error.message, "subagent_spawn"
  end

  test "conversation preview does not instantiate a synthetic turn" do
    registration = register_profile_aware_runtime!
    conversation = create_root_conversation_for!(registration)
    original_new = Turn.method(:new)

    Turn.define_singleton_method(:new) do |*args, **kwargs|
      raise "unexpected synthetic turn preview"
    end

    contract = RuntimeCapabilities::PreviewForConversation.call(conversation: conversation)

    assert_includes contract.fetch("tool_catalog").map { |entry| entry.fetch("tool_name") }, "subagent_spawn"
  ensure
    Turn.define_singleton_method(:new, original_new) if original_new
  end

  test "subagent spawn schema advertises runtime profile choices and default alias" do
    registration = register_profile_aware_runtime!
    conversation = create_root_conversation_for!(registration)

    entry = RuntimeCapabilities::PreviewForConversation.call(
      conversation: conversation
    ).fetch("tool_catalog").find { |tool| tool.fetch("tool_name") == "subagent_spawn" }

    profile_key_schema = entry.fetch("input_schema").fetch("properties").fetch("profile_key")

    assert_equal %w[default main researcher], profile_key_schema.fetch("enum")
    assert_includes profile_key_schema.fetch("description"), "omit this field"
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

  def register_profile_aware_runtime!(execution_runtime_capability_payload: {}, execution_runtime_tool_catalog: [], tool_catalog: default_tool_catalog("exec_command"), profile_catalog: default_profile_catalog, default_config_snapshot: profile_aware_default_config_snapshot)
    register_agent_runtime!(
      execution_runtime_capability_payload: execution_runtime_capability_payload,
      execution_runtime_tool_catalog: execution_runtime_tool_catalog,
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
        agent: registration[:agent]
      )
    )

    Conversations::CreateRoot.call(
      workspace: workspace,
      execution_runtime: registration[:execution_runtime],
      agent_snapshot: registration[:agent_snapshot]
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
        execution_runtime: registration[:execution_runtime],
        agent_snapshot: registration[:agent_snapshot],
        addressability: "agent_addressable"
      )
      session = SubagentConnection.create!(
        installation: registration[:installation],
        conversation: conversation,
        owner_conversation: previous_conversation,
        parent_subagent_connection: previous_session,
        scope: "conversation",
        profile_key: profile_key,
        depth: index
      )

      previous_conversation = conversation
      previous_session = session
    end

    {
      conversation: previous_conversation,
      subagent_connection: previous_session,
    }
  end

  def profile_catalog_with_allowed_tool_names(main_tool_names:, researcher_tool_names:)
    default_profile_catalog.deep_merge(
      "main" => { "allowed_tool_names" => main_tool_names },
      "researcher" => { "allowed_tool_names" => researcher_tool_names }
    )
  end
end
