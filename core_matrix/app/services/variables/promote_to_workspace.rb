module Variables
  class PromoteToWorkspace
    include Conversations::RetentionGuard

    def self.call(...)
      new(...).call
    end

    def initialize(conversation:, key:, writer: nil)
      @conversation = conversation
      @key = key.to_s
      @writer = writer
    end

    def call
      ensure_conversation_retained!(@conversation, message: "must be retained before promotion")
      visible_value = CanonicalStores::GetQuery.call(reference_owner: @conversation, key: @key)
      raise ActiveRecord::RecordNotFound, "conversation variable is missing" if visible_value.blank?

      Variables::Write.call(
        scope: "workspace",
        workspace: @conversation.workspace,
        key: @key,
        typed_value_payload: visible_value.typed_value_payload,
        writer: @writer,
        source_kind: "promotion",
        source_conversation: @conversation
      )
    end
  end
end
