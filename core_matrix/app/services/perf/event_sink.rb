require "fileutils"
require "json"
require "date"
require "time"

module Perf
  class EventSink
    EVENT_PATTERN = /\Aperf\./.freeze
    GENERIC_STRING_ID_KEYS = %w[execution_runtime_connection_id].freeze
    RESERVED_KEYS = %w[recorded_at source_app instance_label event_name duration_ms].freeze

    class << self
      def install!(env: ENV, source_app:, notifier: ActiveSupport::Notifications)
        reset!

        output_path = preferred_env_value(
          env: env,
          source_app: source_app,
          suffix: "PERF_EVENTS_PATH",
          fallback: ""
        )
        return if output_path.empty?

        @current = new(
          output_path: output_path,
          source_app: source_app,
          instance_label: preferred_env_value(
            env: env,
            source_app: source_app,
            suffix: "PERF_INSTANCE_LABEL",
            fallback: source_app
          ),
          notifier: notifier
        ).tap(&:install!)
      end

      def reset!
        @current&.uninstall!
        @current = nil
      end

      def enabled?
        !@current.nil?
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

    def initialize(output_path:, source_app:, instance_label:, notifier:)
      @output_path = output_path
      @source_app = source_app
      @instance_label = instance_label
      @notifier = notifier
      @subscription = nil
    end

    def install!
      @subscription = @notifier.subscribe(EVENT_PATTERN) do |name, started, finished, _unique_id, payload|
        append_event(name: name, started: started, finished: finished, payload: payload || {})
      end
    end

    def uninstall!
      return unless @subscription

      @notifier.unsubscribe(@subscription)
      @subscription = nil
    end

    private

    def append_event(name:, started:, finished:, payload:)
      started_at = normalize_timestamp(started)
      finished_at = normalize_timestamp(finished)

      event = {
        "recorded_at" => finished_at.utc.iso8601(6),
        "source_app" => @source_app,
        "instance_label" => @instance_label,
        "event_name" => name,
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

    def drop_identifier_key?(key)
      key.end_with?("_id") && !key.end_with?("_public_id") && !GENERIC_STRING_ID_KEYS.include?(key)
    end
  end
end
