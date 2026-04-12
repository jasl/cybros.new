class WorkbenchChannel < ApplicationCable::Channel
  def subscribed
    reject and return if current_user.blank?

    conversation = Conversation.find_by!(
      public_id: params.fetch("conversation_id"),
      installation_id: current_user.installation_id,
      deletion_state: "retained"
    )
    reject and return unless AppSurface::Policies::ConversationAccess.call(
      user: current_user,
      conversation: conversation
    )

    stream_from ConversationRuntime::StreamName.for_app_conversation(conversation)
  rescue ActiveRecord::RecordNotFound, KeyError
    reject
  end
end
