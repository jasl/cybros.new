require "test_helper"

class ConversationExecutionEpochs::InitializeCurrentTest < ActiveSupport::TestCase
  test "creates the initial epoch and caches it on the conversation" do
    context = create_workspace_context!
    conversation = create_conversation_without_epoch!(context:, execution_runtime: context[:execution_runtime])

    assert_nil conversation.current_execution_epoch
    assert_equal "not_started", conversation.execution_continuity_state

    epoch = ConversationExecutionEpochs::InitializeCurrent.call(conversation: conversation)

    assert_equal conversation.reload.current_execution_epoch, epoch
    assert_equal context[:execution_runtime], epoch.execution_runtime
    assert_equal context[:execution_runtime], conversation.current_execution_runtime
    assert_equal "ready", conversation.execution_continuity_state
    assert_equal 1, epoch.sequence
  end

  test "is idempotent when the conversation already has a current epoch" do
    context = create_workspace_context!
    conversation = create_conversation_without_epoch!(context:, execution_runtime: context[:execution_runtime])
    first_epoch = ConversationExecutionEpochs::InitializeCurrent.call(conversation: conversation)

    assert_equal first_epoch, ConversationExecutionEpochs::InitializeCurrent.call(conversation: conversation)
    assert_equal 1, conversation.reload.execution_epochs.count
    assert_equal "ready", conversation.execution_continuity_state
  end

  test "allows a conversation to initialize without an execution runtime" do
    installation = create_installation!
    agent = create_agent!(installation: installation, default_execution_runtime: nil)
    user = create_user!(installation: installation)
    workspace = create_workspace!(
      installation: installation,
      user: user,
      agent: agent,
      default_execution_runtime: nil
    )
    conversation = create_conversation_without_epoch!(
      context: {
        installation: installation,
        workspace: workspace,
        agent: agent,
      },
      execution_runtime: nil
    )

    epoch = ConversationExecutionEpochs::InitializeCurrent.call(conversation: conversation)

    assert_nil epoch.execution_runtime
    assert_nil conversation.reload.current_execution_runtime
    assert_equal epoch, conversation.current_execution_epoch
  end

  private

  def create_conversation_without_epoch!(context:, execution_runtime:)
    conversation = Conversation.create!(
      installation: context.fetch(:installation),
      workspace: context.fetch(:workspace),
      agent: context.fetch(:agent),
      user_id: context.fetch(:workspace).user_id,
      current_execution_runtime: execution_runtime,
      kind: "root",
      purpose: "interactive",
      lifecycle_state: "active"
    )
    conversation.update_columns(current_execution_epoch_id: nil)
    ConversationExecutionEpoch.where(conversation: conversation).delete_all
    conversation.reload
  end
end
