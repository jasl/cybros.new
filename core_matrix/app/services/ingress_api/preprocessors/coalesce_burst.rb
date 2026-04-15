module IngressAPI
  module Preprocessors
    class CoalesceBurst
      def self.call(...)
        new(...).call
      end

      def initialize(context:)
        @context = context
      end

      def call
        @context.append_trace("coalesce_burst")
        @context.coalesced_message_ids ||= []
        @context
      end
    end
  end
end
