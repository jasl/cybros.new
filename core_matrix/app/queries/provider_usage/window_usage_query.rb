module ProviderUsage
  class WindowUsageQuery
    Entry = Struct.new(
      :window_key,
      :provider_handle,
      :model_ref,
      :operation_kind,
      :event_count,
      :success_count,
      :failure_count,
      :input_tokens_total,
      :output_tokens_total,
      :cached_input_tokens_total,
      :prompt_cache_available_event_count,
      :prompt_cache_unknown_event_count,
      :prompt_cache_unsupported_event_count,
      :media_units_total,
      :total_latency_ms,
      :estimated_cost_total,
      keyword_init: true
    )

    def self.call(...)
      new(...).call
    end

    def initialize(installation:, window_key:)
      @installation = installation
      @window_key = window_key
    end

    def call
      UsageRollup
        .where(
          installation: @installation,
          bucket_kind: "rolling_window",
          bucket_key: @window_key
        )
        .group(:provider_handle, :model_ref, :operation_kind)
        .order(:provider_handle, :model_ref, :operation_kind)
        .pluck(
          :provider_handle,
          :model_ref,
          :operation_kind,
          Arel.sql("SUM(event_count)"),
          Arel.sql("SUM(success_count)"),
          Arel.sql("SUM(failure_count)"),
          Arel.sql("SUM(input_tokens_total)"),
          Arel.sql("SUM(output_tokens_total)"),
          Arel.sql("SUM(cached_input_tokens_total)"),
          Arel.sql("SUM(prompt_cache_available_event_count)"),
          Arel.sql("SUM(prompt_cache_unknown_event_count)"),
          Arel.sql("SUM(prompt_cache_unsupported_event_count)"),
          Arel.sql("SUM(media_units_total)"),
          Arel.sql("SUM(total_latency_ms)"),
          Arel.sql("SUM(estimated_cost_total)")
        )
        .map do |provider_handle, model_ref, operation_kind, event_count, success_count, failure_count, input_tokens_total, output_tokens_total, cached_input_tokens_total, prompt_cache_available_event_count, prompt_cache_unknown_event_count, prompt_cache_unsupported_event_count, media_units_total, total_latency_ms, estimated_cost_total|
          Entry.new(
            window_key: @window_key,
            provider_handle: provider_handle,
            model_ref: model_ref,
            operation_kind: operation_kind,
            event_count: event_count,
            success_count: success_count,
            failure_count: failure_count,
            input_tokens_total: input_tokens_total,
            output_tokens_total: output_tokens_total,
            cached_input_tokens_total: cached_input_tokens_total,
            prompt_cache_available_event_count: prompt_cache_available_event_count,
            prompt_cache_unknown_event_count: prompt_cache_unknown_event_count,
            prompt_cache_unsupported_event_count: prompt_cache_unsupported_event_count,
            media_units_total: media_units_total,
            total_latency_ms: total_latency_ms,
            estimated_cost_total: estimated_cost_total
          )
        end
    end
  end
end
