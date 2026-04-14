require "test_helper"

class Conversations::Metadata::BootstrapTitleJobTest < ActiveSupport::TestCase
  test "first manual user turn upgrades the placeholder title asynchronously" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])
    turn, message = create_manual_user_turn!(
      context: context,
      conversation: conversation,
      content: "Plan the launch checklist. Include rollback steps."
    )
    invoked = nil

    original_call = Conversations::Metadata::GenerateBootstrapTitle.method(:call)
    Conversations::Metadata::GenerateBootstrapTitle.singleton_class.send(:define_method, :call) do |**kwargs|
      invoked = kwargs
      "Launch checklist plan"
    end

    Conversations::Metadata::BootstrapTitleJob.perform_now(conversation.public_id, turn.public_id)

    conversation.reload
    assert_equal conversation.id, invoked.fetch(:conversation).id
    assert_equal message.id, invoked.fetch(:message).id
    assert_equal "Launch checklist plan", conversation.title
    assert_equal "bootstrap", conversation.title_source
    assert_not_nil conversation.title_updated_at
  ensure
    Conversations::Metadata::GenerateBootstrapTitle.singleton_class.send(:define_method, :call, original_call)
  end

  test "later manual turns do not overwrite the placeholder title" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])
    create_manual_user_turn!(
      context: context,
      conversation: conversation,
      content: "First turn decides the title."
    )
    later_turn, = create_manual_user_turn!(
      context: context,
      conversation: conversation,
      content: "Second turn should not bootstrap the title."
    )
    invoked = false

    original_call = Conversations::Metadata::GenerateBootstrapTitle.method(:call)
    Conversations::Metadata::GenerateBootstrapTitle.singleton_class.send(:define_method, :call) do |**_kwargs|
      invoked = true
      "unexpected"
    end

    Conversations::Metadata::BootstrapTitleJob.perform_now(conversation.public_id, later_turn.public_id)

    conversation.reload
    assert_equal false, invoked
    assert_equal I18n.t("conversations.defaults.untitled_title"), conversation.title
    assert_equal "none", conversation.title_source
  ensure
    Conversations::Metadata::GenerateBootstrapTitle.singleton_class.send(:define_method, :call, original_call)
  end

  test "user-locked titles are preserved" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])
    turn, = create_manual_user_turn!(
      context: context,
      conversation: conversation,
      content: "Attempt to replace the locked title."
    )
    conversation.update!(
      title: "Pinned title",
      title_source: "user",
      title_lock_state: "user_locked",
      title_updated_at: Time.zone.parse("2026-04-14 10:00:00")
    )
    invoked = false

    original_call = Conversations::Metadata::GenerateBootstrapTitle.method(:call)
    Conversations::Metadata::GenerateBootstrapTitle.singleton_class.send(:define_method, :call) do |**_kwargs|
      invoked = true
      "unexpected"
    end

    Conversations::Metadata::BootstrapTitleJob.perform_now(conversation.public_id, turn.public_id)

    conversation.reload
    assert_equal false, invoked
    assert_equal "Pinned title", conversation.title
    assert_equal "user", conversation.title_source
    assert_equal "user_locked", conversation.title_lock_state
  ensure
    Conversations::Metadata::GenerateBootstrapTitle.singleton_class.send(:define_method, :call, original_call)
  end

  test "ineligible turns leave the placeholder title unchanged" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])
    turn = Turn.create!(
      installation: conversation.installation,
      conversation: conversation,
      user: conversation.user,
      workspace: conversation.workspace,
      agent: conversation.agent,
      agent_definition_version: context[:agent_definition_version],
      execution_runtime: context[:execution_runtime],
      execution_epoch: initialize_current_execution_epoch!(conversation, execution_runtime: context[:execution_runtime]),
      sequence: 1,
      lifecycle_state: "active",
      origin_kind: "system_internal",
      origin_payload: {},
      source_ref_type: "User",
      source_ref_id: context[:user].public_id,
      pinned_agent_definition_fingerprint: context[:agent_definition_version].definition_fingerprint,
      agent_config_version: 1,
      agent_config_content_fingerprint: context[:agent_definition_version].definition_fingerprint,
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    invoked = false

    original_call = Conversations::Metadata::GenerateBootstrapTitle.method(:call)
    Conversations::Metadata::GenerateBootstrapTitle.singleton_class.send(:define_method, :call) do |**_kwargs|
      invoked = true
      "unexpected"
    end

    Conversations::Metadata::BootstrapTitleJob.perform_now(conversation.public_id, turn.public_id)

    conversation.reload
    assert_equal false, invoked
    assert_equal I18n.t("conversations.defaults.untitled_title"), conversation.title
    assert_equal "none", conversation.title_source
  ensure
    Conversations::Metadata::GenerateBootstrapTitle.singleton_class.send(:define_method, :call, original_call)
  end

  test "live workspace feature changes can disable title bootstrap before the job runs" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])
    turn, = create_manual_user_turn!(
      context: context,
      conversation: conversation,
      content: "This title should remain a placeholder."
    )
    context[:workspace].update!(
      config: {
        "features" => {
          "title_bootstrap" => {
            "strategy" => "disabled",
          },
        },
      }
    )

    Conversations::Metadata::BootstrapTitleJob.perform_now(conversation.public_id, turn.public_id)

    conversation.reload
    assert_equal I18n.t("conversations.defaults.untitled_title"), conversation.title
    assert_equal "none", conversation.title_source
  end

  private

  def create_manual_user_turn!(context:, conversation:, content:)
    execution_epoch = initialize_current_execution_epoch!(conversation, execution_runtime: context[:execution_runtime])
    turn = Turn.create!(
      installation: conversation.installation,
      conversation: conversation,
      user: conversation.user,
      workspace: conversation.workspace,
      agent: conversation.agent,
      agent_definition_version: context[:agent_definition_version],
      execution_runtime: context[:execution_runtime],
      execution_epoch: execution_epoch,
      sequence: conversation.turns.maximum(:sequence).to_i + 1,
      lifecycle_state: "active",
      origin_kind: "manual_user",
      origin_payload: {},
      source_ref_type: "User",
      source_ref_id: context[:user].public_id,
      pinned_agent_definition_fingerprint: context[:agent_definition_version].definition_fingerprint,
      agent_config_version: 1,
      agent_config_content_fingerprint: context[:agent_definition_version].definition_fingerprint,
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    message = UserMessage.create!(
      installation: conversation.installation,
      conversation: conversation,
      turn: turn,
      role: "user",
      slot: "input",
      variant_index: 0,
      content: content
    )
    Turns::PersistSelectionState.call(turn: turn, selected_input_message: message)

    [turn, message]
  end
end
