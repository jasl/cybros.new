module RuntimeFeatures
  module TitleBootstrap
    class Orchestrator
      def self.call(...)
        new(...).call
      end

      def initialize(definition:, policy:, capability:, request_payload:, feature_request_exchange:, logger: Rails.logger)
        @definition = definition
        @policy = policy
        @capability = capability
        @request_payload = request_payload.deep_stringify_keys
        @feature_request_exchange = feature_request_exchange
        @logger = logger
      end

      def call
        case @policy.fetch("strategy")
        when "disabled"
          failure("feature_disabled")
        when "embedded_only"
          embedded_result
        when "runtime_required"
          runtime_result(required: true)
        else
          runtime_result(required: false)
        end
      end

      private

      def runtime_result(required:)
        return failure("runtime_feature_unavailable") unless @capability.fetch("available")

        response = @feature_request_exchange.execute_feature(
          feature_key: @definition.key,
          request_payload: @request_payload,
          conversation_id: @request_payload["conversation_id"],
          turn_id: @request_payload["turn_id"]
        )

        {
          "status" => "ok",
          "source" => "runtime",
          "result" => response.fetch("result", {}),
          "fallback_used" => false,
        }
      rescue RuntimeFeatures::FeatureRequestExchange::RequestFailed => error
        return failure(error.code) if required

        embedded_result(
          fallback_used: true,
          runtime_failure_code: error.code
        )
      rescue StandardError => error
        @logger.info("runtime title bootstrap fallback: #{error.class}: #{error.message}")
        return failure("feature_execution_failed") if required

        embedded_result(
          fallback_used: true,
          runtime_failure_code: "feature_execution_failed"
        )
      end

      def embedded_result(fallback_used: false, runtime_failure_code: nil)
        result = @definition.embedded_executor_class.call(request_payload: @request_payload)

        {
          "status" => "ok",
          "source" => "embedded",
          "result" => result.deep_stringify_keys,
          "fallback_used" => fallback_used,
          "runtime_failure_code" => runtime_failure_code,
        }.compact
      end

      def failure(code)
        {
          "status" => "failed",
          "code" => code,
          "source" => "runtime",
        }
      end
    end
  end
end
