require "yaml"

module RuntimeTopology
  class CoreMatrix
    InvalidTopology = Class.new(StandardError)
    PATH = Rails.root.join("config/runtime_topology.yml")

    class << self
      def load(path: PATH)
        raw = ActiveSupport::ConfigurationFile.parse(path) || {}
        config = deep_stringify(raw)

        validate_presence!(config, "dispatchers")
        validate_presence!(config, "llm_queues")
        validate_presence!(config, "shared_queues")

        config
      end

      def llm_queue_name(provider_handle, config: load)
        config.fetch("llm_queues").fetch(provider_handle.to_s).fetch("queue")
      rescue KeyError
        raise InvalidTopology, "missing llm queue topology for provider #{provider_handle}"
      end

      def shared_queue_name(queue_key, config: load)
        config.fetch("shared_queues").fetch(queue_key.to_s).fetch("queue")
      rescue KeyError
        raise InvalidTopology, "missing shared queue topology for #{queue_key}"
      end

      private

      def deep_stringify(value)
        case value
        when Hash
          value.each_with_object({}) do |(key, nested_value), normalized|
            normalized[key.to_s] = deep_stringify(nested_value)
          end
        when Array
          value.map { |entry| deep_stringify(entry) }
        else
          value
        end
      end

      def validate_presence!(config, key)
        value = config[key]
        raise InvalidTopology, "runtime topology #{key} must be present" unless value.is_a?(Hash) || value.is_a?(Array)
        raise InvalidTopology, "runtime topology #{key} must not be empty" if value.empty?
      end
    end
  end
end
