require "test_helper"

class ProviderExecution::FailureClassificationTest < ActiveSupport::TestCase
  test "classifies provider rate limiting as external dependency blocked" do
    error = ProviderExecution::ProviderRequestGovernor::AdmissionRefused.new(
      provider_handle: "openrouter",
      reason: "upstream_rate_limit",
      retry_at: Time.zone.parse("2026-04-03 10:05:00 UTC")
    )

    classification = ProviderExecution::FailureClassification.call(error: error)

    assert_equal "external_dependency_blocked", classification.failure_category
    assert_equal "provider_rate_limited", classification.failure_kind
    assert_equal "external_dependency_blocked", classification.wait_reason_kind
    assert_equal "automatic", classification.retry_strategy
    assert_equal 2, classification.max_auto_retries
    refute classification.terminal?
    assert_equal error.retry_at, classification.next_retry_at
  end

  test "classifies provider credits exhaustion as a manual external block" do
    error = build_provider_http_error(
      message: "This request requires more credits, or fewer max_tokens.",
      status: 402
    )

    classification = ProviderExecution::FailureClassification.call(error: error)

    assert_equal "external_dependency_blocked", classification.failure_category
    assert_equal "provider_credits_exhausted", classification.failure_kind
    assert_equal "manual", classification.retry_strategy
    assert_nil classification.next_retry_at
    refute classification.terminal?
  end

  test "classifies provider auth expiry as a manual external block" do
    error = build_provider_http_error(
      message: "Invalid API key",
      status: 401
    )

    classification = ProviderExecution::FailureClassification.call(error: error)

    assert_equal "external_dependency_blocked", classification.failure_category
    assert_equal "provider_auth_expired", classification.failure_kind
    assert_equal "external_dependency_blocked", classification.wait_reason_kind
    assert_equal "manual", classification.retry_strategy
    assert_nil classification.next_retry_at
    refute classification.terminal?
  end

  test "classifies provider overload as an automatic external block" do
    error = build_provider_http_error(
      message: "Upstream overloaded",
      status: 503
    )

    classification = ProviderExecution::FailureClassification.call(error: error)

    assert_equal "external_dependency_blocked", classification.failure_category
    assert_equal "provider_overloaded", classification.failure_kind
    assert_equal "external_dependency_blocked", classification.wait_reason_kind
    assert_equal "automatic", classification.retry_strategy
    assert_equal 2, classification.max_auto_retries
    refute classification.terminal?
  end

  test "classifies provider connection failures as an automatic external block" do
    classification = ProviderExecution::FailureClassification.call(
      error: SimpleInference::ConnectionError.new("dial tcp timeout")
    )

    assert_equal "external_dependency_blocked", classification.failure_category
    assert_equal "provider_unreachable", classification.failure_kind
    assert_equal "external_dependency_blocked", classification.wait_reason_kind
    assert_equal "automatic", classification.retry_strategy
    assert_equal 2, classification.max_auto_retries
    refute classification.terminal?
  end

  test "classifies invalid agent responses as retryable contract errors" do
    error = ProviderExecution::AgentRequestExchange::ProtocolError.new(
      code: "invalid_prepare_round_response",
      message: "prepare_round response must include messages"
    )

    classification = ProviderExecution::FailureClassification.call(error: error)

    assert_equal "contract_error", classification.failure_category
    assert_equal "invalid_agent_response_contract", classification.failure_kind
    assert_equal "retryable_failure", classification.wait_reason_kind
    assert_equal "automatic", classification.retry_strategy
    refute classification.terminal?
  end

  test "classifies invalid provider responses as retryable contract errors" do
    classification = ProviderExecution::FailureClassification.call(
      error: SimpleInference::DecodeError.new("provider response must include output text or tool calls")
    )

    assert_equal "contract_error", classification.failure_category
    assert_equal "invalid_provider_response_contract", classification.failure_kind
    assert_equal "retryable_failure", classification.wait_reason_kind
    assert_equal "automatic", classification.retry_strategy
    refute classification.terminal?
  end

  test "classifies selected-input prompt failures as manual retryable failures" do
    error = ProviderExecution::ExecuteRoundLoop::PromptTooLargeForRetry.new(
      messages_count: 3,
      selected_input_message_id: "msg-current"
    )

    classification = ProviderExecution::FailureClassification.call(error: error)

    assert_equal "contract_error", classification.failure_category
    assert_equal "prompt_too_large_for_retry", classification.failure_kind
    assert_equal "retryable_failure", classification.wait_reason_kind
    assert_equal "manual", classification.retry_strategy
    assert_equal 0, classification.max_auto_retries
    refute classification.terminal?
  end

  test "classifies post-compaction context overflow as a manual retryable failure" do
    error = ProviderExecution::ExecuteRoundLoop::ContextWindowExceededAfterCompaction.new(
      messages_count: 4,
      selected_input_message_id: "msg-current"
    )

    classification = ProviderExecution::FailureClassification.call(error: error)

    assert_equal "contract_error", classification.failure_category
    assert_equal "context_window_exceeded_after_compaction", classification.failure_kind
    assert_equal "retryable_failure", classification.wait_reason_kind
    assert_equal "manual", classification.retry_strategy
    assert_equal 0, classification.max_auto_retries
    refute classification.terminal?
  end

  test "classifies provider-side context overflow as an explicit prompt-size failure" do
    error = build_provider_http_error(
      message: "This model's maximum context length is 128000 tokens, however you requested 145031 tokens.",
      status: 400,
      body: {
        "error" => {
          "code" => "context_length_exceeded",
          "message" => "This model's maximum context length is 128000 tokens, however you requested 145031 tokens.",
        },
      }
    )

    classification = ProviderExecution::FailureClassification.call(error: error)

    assert_equal "contract_error", classification.failure_category
    assert_equal "context_window_exceeded_after_compaction", classification.failure_kind
    assert_equal "retryable_failure", classification.wait_reason_kind
    assert_equal "manual", classification.retry_strategy
    refute classification.terminal?
  end

  test "classifies requested-token overflow signatures as explicit prompt-size failures" do
    error = build_provider_http_error(
      message: "Provider rejected the request because you requested 145031 tokens.",
      status: 400
    )

    classification = ProviderExecution::FailureClassification.call(error: error)

    assert_equal "contract_error", classification.failure_category
    assert_equal "context_window_exceeded_after_compaction", classification.failure_kind
    assert_equal "retryable_failure", classification.wait_reason_kind
    assert_equal "manual", classification.retry_strategy
    refute classification.terminal?
  end

  test "classifies unknown errors as terminal implementation failures" do
    classification = ProviderExecution::FailureClassification.call(error: StandardError.new("boom"))

    assert_equal "implementation_error", classification.failure_category
    assert_equal "internal_unexpected_error", classification.failure_kind
    assert classification.terminal?
    assert_nil classification.wait_reason_kind
  end
end
