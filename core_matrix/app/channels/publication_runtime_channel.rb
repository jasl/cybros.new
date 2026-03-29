class PublicationRuntimeChannel < ApplicationCable::Channel
  def subscribed
    return reject unless current_publication.present?

    stream_from ConversationRuntime::StreamName.for_conversation(current_publication.conversation)
  end
end
