require "date"
require "fileutils"
require "json"
require "time"

module CybrosNexus
  module Perf
    class NullEventSink
      def enabled?
        false
      end

      def record(...)
        nil
      end

      def instrument(_event_name, payload: {})
        yield
      end
    end

    class EventSink
      GENERIC_STRING_ID_KEYS = %w[execution_runtime_connection_id].freeze
      RESERVED_KEYS = %w[recorded_at source_app instance_label event_name duration_ms].freeze

      class << self
        def build(env: ENV, source_app:)
          output_path = preferred_env_value(
            env: env,
            source_app: source_app,
            suffix: "PERF_EVENTS_PATH",
            fallback: ""
          )
          return NullEventSink.new if output_path.empty?

          new(
            output_path: output_path,
            source_app: source_app,
            instance_label: preferred_env_value(
              env: env,
              source_app: source_app,
              suffix: "PERF_INSTANCE_LABEL",
              fallback: source_app
            )
          )
        end

        private

        def preferred_env_value(env:, source_app:, suffix:, fallback:)
          source_key = "#{source_app.upcase}_#{suffix}"
          preferred = env[source_key].to_s
          return preferred unless preferred.empty?

          shared_key = "CYBROS_#{suffix}"
          shared = env[shared_key].to_s
          return shared unless shared.empty?

          fallback
        end
      end

      def initialize(output_path:, source_app:, instance_label:)
        @output_path = output_path
        @source_app = source_app
        @instance_label = instance_label
      end

      def enabled?
        true
      end

      def record(event_name, payload: {}, started_at: Time.now, finished_at: Time.now)
        append_event(
          event_name: event_name,
          payload: payload,
          started_at: normalize_timestamp(started_at),
          finished_at: normalize_timestamp(finished_at)
        )
      end

      def instrument(event_name, payload: {})
        started_at = Time.now
        result = yield
        record(event_name, payload: payload, started_at: started_at, finished_at: Time.now)
        result
      rescue StandardError
        failure_payload = payload.key?("success") ? payload : payload.merge("success" => false)
        record(event_name, payload: failure_payload, started_at: started_at, finished_at: Time.now)
        raise
      end

      private

      def append_event(event_name:, payload:, started_at:, finished_at:)
        event = {
          "recorded_at" => finished_at.utc.iso8601(6),
          "source_app" => @source_app,
          "instance_label" => @instance_label,
          "event_name" => event_name,
          "duration_ms" => ((finished_at - started_at) * 1000.0).round(3),
        }.merge(sanitize_hash(payload))

        FileUtils.mkdir_p(File.dirname(@output_path))
        File.open(@output_path, "a") do |file|
          file.flock(File::LOCK_EX)
          file.puts(JSON.generate(event))
        end
      end

      def sanitize_hash(hash)
        hash.each_with_object({}) do |(key, value), sanitized|
          normalized_key = key.to_s
          next if RESERVED_KEYS.include?(normalized_key)
          next if drop_identifier_key?(normalized_key)

          sanitized_value = sanitize_value(value)
          next if sanitized_value.nil?

          sanitized[normalized_key] = sanitized_value
        end
      end

      def sanitize_value(value)
        case value
        when Hash
          sanitized = sanitize_hash(value)
          sanitized.empty? ? nil : sanitized
        when Array
          sanitized = value.filter_map { |entry| sanitize_value(entry) }
          sanitized.empty? ? nil : sanitized
        when Time, Date, DateTime
          value.iso8601(6)
        when String, Numeric, TrueClass, FalseClass
          value
        else
          nil
        end
      end

      def normalize_timestamp(value)
        case value
        when Time
          value
        when DateTime
          value.to_time
        when Numeric
          Time.at(value).utc
        else
          raise ArgumentError, "unsupported perf timestamp: #{value.inspect}"
        end
      end

      def drop_identifier_key?(key)
        key.end_with?("_id") &&
          !key.end_with?("_public_id") &&
          !GENERIC_STRING_ID_KEYS.include?(key)
      end
    end
  end
end
