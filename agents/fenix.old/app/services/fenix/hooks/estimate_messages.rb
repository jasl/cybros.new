module Fenix
  module Hooks
    class EstimateMessages
      def self.call(messages:)
        Array(messages).size
      end
    end
  end
end
