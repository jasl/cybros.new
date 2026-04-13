require "test_helper"

class Turns::FreezeExecutionIdentityTest < ActiveSupport::TestCase
  test "initializes the first epoch directly on the requested runtime" do
    context = create_workspace_context!
    override_runtime = create_execution_runtime!(
      installation: context[:installation],
      display_name: "Cloud Runtime"
    )
    create_execution_runtime_connection!(
      installation: context[:installation],
      execution_runtime: override_runtime
    )
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])

    with_redefined_singleton_method(
      ConversationExecutionEpochs::RetargetCurrent,
      :call,
      ->(*) { raise "RetargetCurrent should not be called for first-turn override bootstrap" }
    ) do
      identity = Turns::FreezeExecutionIdentity.call(
        conversation: conversation,
        execution_runtime: override_runtime
      )

      assert_equal override_runtime, identity.execution_runtime
      assert_equal override_runtime, identity.execution_epoch.execution_runtime
      assert_equal 1, conversation.reload.execution_epochs.count
    end
  end

  private

  def with_redefined_singleton_method(target, method_name, replacement)
    singleton = target.singleton_class
    original = target.method(method_name)

    singleton.send(:define_method, method_name, replacement)
    yield
  ensure
    singleton.send(:define_method, method_name, original)
  end
end
