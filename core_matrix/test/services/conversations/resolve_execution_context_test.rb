require "test_helper"

class Conversations::ResolveExecutionContextTest < ActiveSupport::TestCase
  test "resolves the active agent definition and runtime without materializing an epoch" do
    registration = register_agent_runtime!
    conversation = create_resolvable_conversation_for!(registration)

    assert_nil conversation.current_execution_epoch

    assert_no_difference("ConversationExecutionEpoch.count") do
      context = Conversations::ResolveExecutionContext.call(conversation: conversation)

      assert_equal registration[:agent_definition_version], context.agent_definition_version
      assert_equal registration[:execution_runtime], context.execution_runtime
      assert_equal registration[:execution_runtime].current_execution_runtime_version, context.execution_runtime_version
    end

    assert_nil conversation.reload.current_execution_epoch
    assert_equal "not_started", conversation.execution_continuity_state
  end

  test "supports an explicit runtime override without materializing an epoch" do
    registration = register_agent_runtime!
    conversation = create_resolvable_conversation_for!(registration)
    override_runtime = create_execution_runtime!(installation: registration[:installation], display_name: "Override Runtime")
    override_runtime_connection = create_execution_runtime_connection!(
      installation: registration[:installation],
      execution_runtime: override_runtime
    )

    context = Conversations::ResolveExecutionContext.call(
      conversation: conversation,
      execution_runtime: override_runtime
    )

    assert_equal override_runtime, context.execution_runtime
    assert_equal override_runtime_connection.execution_runtime_version, context.execution_runtime_version
    assert_nil conversation.reload.current_execution_epoch
  end

  test "raises when the conversation agent has no active connection" do
    registration = register_agent_runtime!
    conversation = create_resolvable_conversation_for!(registration)
    registration[:agent_connection].update!(lifecycle_state: "stale")

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Conversations::ResolveExecutionContext.call(conversation: conversation)
    end

    assert_includes error.record.errors[:agent], "must have an active agent connection for turn entry"
  end

  test "returns nil runtime context when unavailable runtimes are tolerated" do
    registration = register_agent_runtime!
    conversation = create_resolvable_conversation_for!(registration)
    registration[:execution_runtime_connection].update!(lifecycle_state: "closed")
    registration[:execution_runtime].update_columns(current_execution_runtime_version_id: nil, published_execution_runtime_version_id: nil)

    context = Conversations::ResolveExecutionContext.call(
      conversation: conversation,
      allow_unavailable_execution_runtime: true
    )

    assert_equal registration[:agent_definition_version], context.agent_definition_version
    assert_nil context.execution_runtime
    assert_nil context.execution_runtime_version
    assert_nil conversation.reload.current_execution_epoch
  end

  private

  def create_resolvable_conversation_for!(registration)
    workspace = create_workspace!(
      installation: registration[:installation],
      user: registration[:actor],
      default_execution_runtime: registration[:execution_runtime],
      agent: registration[:agent]
    )

    Conversations::CreateRoot.call(workspace: workspace)
  end
end
