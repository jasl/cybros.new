module Conversations
  class WithRetainedLifecycleLock
    def self.call(*args, **kwargs, &block)
      new(*args, **kwargs).call(&block)
    end

    def initialize(
      conversation:,
      record: nil,
      retained_attribute: :deletion_state,
      retained_message:,
      lifecycle_attribute: :lifecycle_state,
      expected_state:,
      lifecycle_message:
    )
      @conversation = conversation
      @record = record || conversation
      @retained_attribute = retained_attribute
      @retained_message = retained_message
      @lifecycle_attribute = lifecycle_attribute
      @expected_state = expected_state.to_s
      @lifecycle_message = lifecycle_message
    end

    def call
      Conversations::WithRetainedStateLock.call(
        conversation: @conversation,
        record: @record,
        attribute: @retained_attribute,
        message: @retained_message
      ) do |conversation|
        return yield conversation if conversation.lifecycle_state == @expected_state

        @record.errors.add(@lifecycle_attribute, @lifecycle_message)
        raise ActiveRecord::RecordInvalid, @record
      end
    end
  end
end
