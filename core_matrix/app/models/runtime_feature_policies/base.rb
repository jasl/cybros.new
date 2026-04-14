module RuntimeFeaturePolicies
  class Base
    STRATEGIES = %w[disabled embedded_only runtime_first runtime_required].freeze

    class << self
      attr_writer :feature_key, :default_strategy

      def feature_key
        @feature_key || raise(NotImplementedError, "#{name} must define .feature_key")
      end

      def default_strategy
        @default_strategy || raise(NotImplementedError, "#{name} must define .default_strategy")
      end

      def default_payload
        { "strategy" => default_strategy }
      end

      def json_schema
        {
          "type" => "object",
          "additionalProperties" => false,
          "properties" => {
            "strategy" => {
              "type" => "string",
              "enum" => STRATEGIES,
              "default" => default_strategy,
            },
          },
          "required" => ["strategy"],
        }
      end

      def normalize(payload)
        values = normalize_hash(payload)
        return {} if values.empty?

        values.slice("strategy")
      end

      def validate!(payload)
        raise ArgumentError, "features.#{feature_key} must be a hash" unless payload.is_a?(Hash)

        values = payload.deep_stringify_keys
        unsupported_keys = values.keys - ["strategy"]
        if unsupported_keys.any?
          raise ArgumentError, "features.#{feature_key}.#{unsupported_keys.first} is not supported"
        end

        return unless values.key?("strategy")
        return if STRATEGIES.include?(values.fetch("strategy"))

        raise ArgumentError, "features.#{feature_key}.strategy must be one of #{STRATEGIES.join(", ")}"
      end

      private

      def normalize_hash(value)
        value.is_a?(Hash) ? value.deep_stringify_keys : {}
      end
    end
  end
end
