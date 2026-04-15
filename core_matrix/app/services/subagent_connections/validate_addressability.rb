module SubagentConnections
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

      @record.errors.add(:entry_policy_payload, @rejection_message)
      raise ActiveRecord::RecordInvalid, @record
    end

    private

    def allowed_sender_kind?
      if HUMAN_SENDER_KINDS.include?(@sender_kind)
        return @conversation.allows_entry_surface?("main_transcript")
      end

      if AGENT_SENDER_KINDS.include?(@sender_kind)
        return @conversation.allows_entry_surface?("agent_internal")
      end

      false
    end
  end
end
