module Conversations
  class AssertFeatureEnabled
    def self.call(...)
      new(...).call
    end

    def initialize(conversation:, feature_id:, record: conversation, attribute: :base)
      @conversation = conversation
      @feature_id = feature_id.to_s
      @record = record
      @attribute = attribute
    end

    def call
      return @conversation if @conversation.feature_enabled?(@feature_id)

      @record.errors.add(@attribute, :feature_not_enabled, feature_id: @feature_id)
      raise ActiveRecord::RecordInvalid, @record
    end
  end
end
