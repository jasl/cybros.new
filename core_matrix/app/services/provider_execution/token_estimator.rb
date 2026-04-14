require "tiktoken_ruby"

module ProviderExecution
  class TokenEstimator
    IMAGE_TOKEN_COST = 1_024
    FILE_TOKEN_COST = 256
    AUDIO_TOKEN_COST = 2_048
    VIDEO_TOKEN_COST = 4_096
    HEURISTIC_CHARS_PER_TOKEN = 4.0

    MODALITY_TYPE_MAP = {
      "input_image" => "image",
      "output_image" => "image",
      "image" => "image",
      "image_url" => "image",
      "input_file" => "file",
      "file" => "file",
      "input_audio" => "audio",
      "audio" => "audio",
      "video" => "video",
    }.freeze
    MODALITY_TOKEN_COSTS = {
      "image" => IMAGE_TOKEN_COST,
      "file" => FILE_TOKEN_COST,
      "audio" => AUDIO_TOKEN_COST,
      "video" => VIDEO_TOKEN_COST,
    }.freeze

    def self.call(...)
      new(...).call
    end

    def initialize(input:, tokenizer_hint:)
      @input = input
      @tokenizer_hint = tokenizer_hint.to_s
      @text_segments = 0
      @modalities = []
      @used_tiktoken = false
    end

    def call
      {
        "estimated_tokens" => estimate_value(@input),
        "strategy" => strategy,
        "diagnostics" => {
          "text_segments" => @text_segments,
          "modalities" => @modalities.uniq.sort,
        },
      }
    end

    private

    def strategy
      @used_tiktoken ? "tiktoken" : "heuristic"
    end

    def estimate_value(value)
      case value
      when String
        estimate_text(value)
      when Array
        value.sum { |entry| estimate_value(entry) }
      when Hash
        estimate_hash(value.deep_stringify_keys)
      else
        estimate_text(value.to_s)
      end
    end

    def estimate_hash(entry)
      type = entry["type"].to_s
      modality = MODALITY_TYPE_MAP[type] || infer_modality(entry)
      return estimate_modality(modality) if modality.present?

      estimated = 0
      estimated += 1 if entry["role"].present?
      estimated += estimate_value(entry["content"]) if entry.key?("content")
      estimated += estimate_value(entry["text"]) if entry["text"].present?
      estimated += estimate_value(entry["arguments"]) if entry["arguments"].present?
      estimated += estimate_value(entry["output"]) if entry["output"].present?

      entry.each do |key, nested_value|
        next if %w[type role content text arguments output].include?(key)

        estimated += estimate_value(nested_value)
      end

      estimated
    end

    def infer_modality(entry)
      return "image" if entry["image_url"].present?
      return "file" if entry["file_id"].present? || entry["file_url"].present?
      return "audio" if entry["audio_url"].present?
      return "video" if entry["video_url"].present?

      nil
    end

    def estimate_modality(modality)
      @modalities << modality
      MODALITY_TOKEN_COSTS.fetch(modality)
    end

    def estimate_text(text)
      candidate = text.to_s
      return 0 if candidate.blank?

      @text_segments += 1
      @modalities << "text"

      if encoder.present?
        @used_tiktoken = true
        encoder.encode(candidate).length
      else
        [(candidate.length / HEURISTIC_CHARS_PER_TOKEN).ceil, 1].max
      end
    end

    def encoder
      return @encoder if defined?(@encoder)

      @encoder = Tiktoken.get_encoding(@tokenizer_hint)
    rescue StandardError
      @encoder = nil
    end
  end
end
