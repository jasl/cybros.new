module Variables
  class PromoteToWorkspace
    def self.call(...)
      new(...).call
    end

    def initialize(conversation:, key:, writer: nil)
      @conversation = conversation
      @key = key.to_s
      @writer = writer
    end

    def call
      Conversations::WithMutableStateLock.call(
        conversation: @conversation,
        record: @conversation,
        retained_message: "must be retained before promotion",
        active_message: "must be active before promotion",
        closing_message: "must not mutate conversation state while close is in progress"
      ) do |conversation|
        visible_value = LineageStores::GetQuery.call(reference_owner: conversation, key: @key)
        raise ActiveRecord::RecordNotFound, "conversation variable is missing" if visible_value.blank?

        Variables::Write.call(
          scope: "workspace",
          workspace: conversation.workspace,
          key: @key,
          typed_value_payload: visible_value.typed_value_payload,
          writer: @writer,
          source_kind: "promotion",
          source_conversation: conversation
        )
      end
    end
  end
end
