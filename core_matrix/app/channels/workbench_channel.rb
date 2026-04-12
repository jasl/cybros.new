class WorkbenchChannel < ApplicationCable::Channel
  def subscribed
    conversation = ConversationRuntime::AuthorizeSubscription.call(
      current_user: current_user,
      conversation_id: params.fetch("conversation_id")
    )

    stream_from ConversationRuntime::StreamName.for_app_conversation(conversation)
  rescue ActiveRecord::RecordNotFound, KeyError
    reject
  end
end
