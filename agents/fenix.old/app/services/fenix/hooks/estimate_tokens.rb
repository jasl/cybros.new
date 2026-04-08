module Fenix
  module Hooks
    class EstimateTokens
      def self.call(messages:)
        Array(messages).sum do |message|
          message.fetch("content", "").to_s.split.size + 4
        end
      end
    end
  end
end
