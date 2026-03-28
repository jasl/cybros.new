module SubagentSessions
  class ValidateAddressability
    HUMAN_SENDER_KINDS = %w[human].freeze
    AGENT_SENDER_KINDS = %w[owner_agent subagent_self system].freeze

    def self.call(...)
      new(...).call
    end

    def initialize(conversation:, sender_kind:, rejection_message:, record: conversation)
      @conversation = conversation
      @sender_kind = sender_kind
      @rejection_message = rejection_message
      @record = record
    end

    def call
      return if allowed_sender_kind?

      @record.errors.add(:addressability, @rejection_message)
      raise ActiveRecord::RecordInvalid, @record
    end

    private

    def allowed_sender_kind?
      return AGENT_SENDER_KINDS.include?(@sender_kind) if @conversation.agent_addressable?

      HUMAN_SENDER_KINDS.include?(@sender_kind)
    end
  end
end
