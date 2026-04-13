require "test_helper"

class Conversations::CreateAutomationRootTest < ActiveSupport::TestCase
  test "creates an active automation root conversation" do
    context = create_workspace_context!

    conversation = Conversations::CreateAutomationRoot.call(
      workspace: context[:workspace],
    )

    assert_equal context[:installation], conversation.installation
    assert_equal context[:workspace], conversation.workspace
    assert conversation.root?
    assert conversation.automation?
    assert conversation.active?
    assert conversation.retained?
    assert_nil conversation.parent_conversation
    assert_nil conversation.historical_anchor_message_id
    assert_equal context[:execution_runtime], conversation.current_execution_runtime
    assert_nil conversation.current_execution_epoch
    assert_equal 0, conversation.execution_epochs.count
    assert_equal "not_started", conversation.execution_continuity_state
    assert_nil conversation.lineage_store_reference
  end

  test "rejects unexpected keyword arguments" do
    context = create_workspace_context!

    assert_raises(ArgumentError) do
      Conversations::CreateAutomationRoot.call(
        workspace: context[:workspace],
        execution_runtime: context[:execution_runtime],
      )
    end
  end
end
