module Conversations
  class AddImport
    def self.call(...)
      new(...).call
    end

    def initialize(conversation:, kind:, source_conversation: nil, source_message: nil, summary_segment: nil)
      @conversation = conversation
      @kind = kind
      @source_conversation = source_conversation
      @source_message = source_message
      @summary_segment = summary_segment
    end

    def call
      attributes = {
        installation: @conversation.installation,
        conversation: @conversation,
        kind: @kind,
        source_conversation: @source_conversation,
        source_message: @source_message,
        summary_segment: @summary_segment,
      }

      return ConversationImport.create!(attributes) unless @kind.to_s == "branch_prefix"

      import = ConversationImport.find_or_initialize_by(
        installation: @conversation.installation,
        conversation: @conversation,
        kind: "branch_prefix"
      )
      import.assign_attributes(attributes.except(:installation, :conversation, :kind))
      import.save!
      import
    end
  end
end
