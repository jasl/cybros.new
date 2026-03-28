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
      import = build_import_record(conversation: @conversation)

      ApplicationRecord.transaction do
        Conversations::WithConversationEntryLock.call(
          conversation: @conversation,
          record: import,
          retained_message: "must be retained before adding imports",
          active_message: "must be active before adding imports",
          closing_message: "must not add imports while close is in progress"
        ) do |conversation|
          import.assign_attributes(import_attributes(conversation:))

          return import.tap(&:save!) unless @kind.to_s == "branch_prefix"

          branch_prefix_import = ConversationImport.find_or_initialize_by(
            installation: conversation.installation,
            conversation: conversation,
            kind: "branch_prefix"
          )
          branch_prefix_import.assign_attributes(import_attributes(conversation:).except(:installation, :conversation, :kind))
          branch_prefix_import.save!
          branch_prefix_import
        end
      end
    end

    private

    def build_import_record(conversation:)
      ConversationImport.new(import_attributes(conversation:))
    end

    def import_attributes(conversation:)
      {
        installation: conversation.installation,
        conversation: conversation,
        kind: @kind,
        source_conversation: @source_conversation,
        source_message: @source_message,
        summary_segment: @summary_segment,
      }
    end
  end
end
