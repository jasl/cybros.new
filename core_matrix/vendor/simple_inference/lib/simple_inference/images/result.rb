# frozen_string_literal: true

module SimpleInference
  module Images
    class Result
      attr_reader :images, :usage, :provider_response, :provider_format, :output_text

      def initialize(images:, usage:, provider_response:, provider_format:, output_text: nil)
        @images = Array(images)
        @usage = usage
        @provider_response = provider_response
        @provider_format = provider_format
        @output_text = output_text
      end
    end
  end
end
