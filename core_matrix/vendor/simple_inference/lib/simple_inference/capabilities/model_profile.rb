# frozen_string_literal: true

module SimpleInference
  module Capabilities
    class ModelProfile
      def initialize(attributes = {})
        @attributes = stringify_hash(attributes)
      end

      def api_model
        @attributes["api_model"].to_s
      end

      def capabilities
        value = @attributes["capabilities"]
        stringify_hash(value)
      end

      def text_output?
        capability_enabled?("text_output")
      end

      def tool_calls?
        capability_enabled?("tool_calls")
      end

      def structured_output?
        capability_enabled?("structured_output")
      end

      def streaming?
        capability_enabled?("streaming")
      end

      def conversation_state?
        capability_enabled?("conversation_state")
      end

      def provider_builtin_tools?
        capability_enabled?("provider_builtin_tools")
      end

      def image_generation?
        capability_enabled?("image_generation")
      end

      def multimodal_inputs
        value = capabilities["multimodal_inputs"]
        stringify_hash(value)
      end

      def multimodal_input_enabled?(kind)
        return true unless multimodal_inputs.key?(kind.to_s)

        multimodal_inputs[kind.to_s] == true
      end

      def to_h
        @attributes.dup
      end

      private

      def capability_enabled?(key)
        return true unless capabilities.key?(key)

        capabilities[key] == true
      end

      def stringify_hash(value)
        return {} unless value.is_a?(Hash)

        value.each_with_object({}) do |(key, entry), out|
          out[key.to_s] = entry
        end
      end
    end
  end
end
