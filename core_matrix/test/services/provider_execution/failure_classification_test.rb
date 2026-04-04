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

  test "classifies invalid program responses as retryable contract errors" do
    error = ProviderExecution::ProgramMailboxExchange::ProtocolError.new(
      code: "invalid_prepare_round_response",
      message: "prepare_round response must include messages"
    )

    classification = ProviderExecution::FailureClassification.call(error: error)

    assert_equal "contract_error", classification.failure_category
    assert_equal "invalid_program_response_contract", classification.failure_kind
    assert_equal "retryable_failure", classification.wait_reason_kind
    assert_equal "automatic", classification.retry_strategy
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
