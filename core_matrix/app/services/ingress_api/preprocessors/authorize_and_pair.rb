module IngressAPI
  module Preprocessors
    class AuthorizeAndPair
      def self.call(...)
        new(...).call
      end

      def initialize(context:)
        @context = context
      end

      def call
        @context.append_trace("authorize_and_pair")
        @context
      end
    end
  end
end
