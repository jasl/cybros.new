module Requests
  class ExecuteFeature
    def self.call(...)
      new(...).call
    end

    def initialize(payload:)
      @payload = payload.deep_stringify_keys
    end

    def call
      case feature_key
      when "title_bootstrap"
        {
          "status" => "ok",
          "result" => {
            "title" => title_from_content,
          },
        }
      else
        {
          "status" => "failed",
          "failure" => {
            "classification" => "semantic",
            "code" => "unsupported_feature",
            "message" => "unsupported feature #{feature_key.inspect}",
            "retryable" => false,
          },
        }
      end
    end

    private

    def feature_key
      @payload.dig("feature", "feature_key").to_s
    end

    def message_content
      @payload.dig("feature", "input", "message_content").to_s
    end

    def title_from_content
      squished = message_content.squish
      candidate = squished.split(/[\.\!\?\n]/).find(&:present?).to_s.squish
      candidate = squished if candidate.blank?
      candidate.first(80).to_s
    end
  end
end
