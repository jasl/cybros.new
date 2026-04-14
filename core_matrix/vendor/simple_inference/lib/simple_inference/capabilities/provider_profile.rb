# frozen_string_literal: true

module SimpleInference
  module Capabilities
    class ProviderProfile
      def initialize(attributes = {})
        @attributes = stringify_hash(attributes)
      end

      def wire_api
        @attributes["wire_api"].to_s
      end

      def responses_path
        value = @attributes["responses_path"].to_s
        value.empty? ? nil : value
      end

      def adapter_key
        @attributes["adapter_key"].to_s
      end

      def to_h
        @attributes.dup
      end

      private

      def stringify_hash(value)
        return {} unless value.is_a?(Hash)

        value.each_with_object({}) do |(key, entry), out|
          out[key.to_s] = entry
        end
      end
    end
  end
end
