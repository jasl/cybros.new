require "test_helper"

module AppSurface
  module Presenters
  end
end

class AppSurface::Presenters::ConversationPresenterTest < ActiveSupport::TestCase
  test "emits only public ids and stable conversation fields" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])
    payload = AppSurface::Presenters::ConversationPresenter.call(conversation: conversation)

    assert_equal conversation.public_id, payload.fetch("conversation_id")
    assert_equal context[:workspace].public_id, payload.fetch("workspace_id")
    assert_equal context[:agent].public_id, payload.fetch("agent_id")
    assert_equal conversation.kind, payload.fetch("kind")
    assert_equal conversation.purpose, payload.fetch("purpose")
    assert_equal conversation.lifecycle_state, payload.fetch("lifecycle_state")
    refute_includes payload.to_json, %("#{conversation.id}")
  end

  test "emits bare-conversation continuity state without a current epoch" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])

    payload = AppSurface::Presenters::ConversationPresenter.call(conversation: conversation)

    assert_equal context[:execution_runtime].public_id, payload.fetch("current_execution_runtime_id")
    assert_nil payload["current_execution_epoch_id"]
    assert_equal "not_started", payload.fetch("execution_continuity_state")
  end
end
