require "test_helper"

module ProviderGateway
end

class ProviderGateway::DispatchTextTest < ActiveSupport::TestCase
  class FlakyChatAdapter < SimpleInference::HTTPAdapter
    attr_reader :requests

    def initialize(response_body:)
      @response_body = response_body
      @requests = []
      @attempt = 0
    end

    def call(env)
      @requests << env
      @attempt += 1

      raise SimpleInference::TimeoutError, "Timed out while resolving provider request" if @attempt == 1

      sleep 0.03

      {
        status: 200,
        headers: {
          "content-type" => "application/json",
          "x-request-id" => "provider-gateway-request-1",
        },
        body: JSON.generate(@response_body),
      }
    end
  end

  class FakeGovernor
    class << self
      attr_accessor :acquire_calls, :renew_calls, :release_calls

      def reset!
        self.acquire_calls = []
        self.renew_calls = []
        self.release_calls = []
      end

      def acquire(**kwargs)
        acquire_calls << kwargs
        ProviderExecution::ProviderRequestGovernor::Decision.new(
          allowed: true,
          provider_handle: kwargs.fetch(:provider_handle),
          reason: nil,
          retry_at: nil,
          lease_token: "lease-123",
          lease_expires_at: Time.current + 1.second
        )
      end

      def renew(**kwargs)
        renew_calls << kwargs
      end

      def release(**kwargs)
        release_calls << kwargs
      end

      def record_rate_limit!(**)
        raise "not expected in this test"
      end

      def retry_after_seconds_for(**)
        1
      end
    end
  end

  setup do
    FakeGovernor.reset!
  end

  test "resolves the selected role and merges request settings through the catalog schema" do
    installation = fresh_installation!
    ProviderEntitlement.create!(
      installation: installation,
      provider_handle: "dev",
      entitlement_key: "dev_window",
      window_kind: "rolling_five_hours",
      window_seconds: 5.hours.to_i,
      quota_limit: 200_000,
      active: true,
      metadata: {}
    )

    catalog_definition = test_provider_catalog_definition.deep_dup
    catalog_definition[:providers][:dev][:models]["mock-model"] = test_model_definition(
      display_name: "Mock Model",
      api_model: "mock-model",
      tokenizer_hint: "o200k_base",
      context_window_tokens: 100,
      max_output_tokens: 24,
      context_soft_limit_ratio: 0.5,
      request_defaults: {
        temperature: 0.7,
        top_p: 0.8,
      }
    )
    catalog_definition[:model_roles]["conversation_title"] = ["dev/mock-model"]
    catalog = build_test_provider_catalog_from(catalog_definition)
    adapter = FlakyChatAdapter.new(
      response_body: {
        id: "chatcmpl-gateway-1",
        choices: [
          {
            message: {
              role: "assistant",
              content: "Draft release notes",
            },
            finish_reason: "stop",
          },
        ],
        usage: {
          prompt_tokens: 5,
          completion_tokens: 2,
          total_tokens: 7,
        },
      }
    )

    result = ProviderGateway::DispatchText.call(
      installation: installation,
      selector: "role:conversation_title",
      messages: [
        { "role" => "system", "content" => "Write a concise title." },
        { "role" => "user", "content" => "Draft release notes for the new retry flow." },
      ],
      max_output_tokens: 24,
      request_overrides: {
        "temperature" => 0.4,
        "sandbox" => "workspace-write",
      },
      purpose: "conversation_title",
      adapter: adapter,
      catalog: catalog,
      governor: FakeGovernor,
      lease_renew_interval_seconds: 0.01
    )

    request_body = JSON.parse(adapter.requests.last.fetch(:body))

    assert_equal "mock-model", request_body.fetch("model")
    assert_equal 0.4, request_body.fetch("temperature")
    assert_equal 0.8, request_body.fetch("top_p")
    assert_equal 24, request_body.fetch("max_tokens")
    refute request_body.key?("sandbox")

    assert_equal "Draft release notes", result.content
    assert_equal "provider-gateway-request-1", result.provider_request_id
    assert_equal(
      {
        "input_tokens" => 5,
        "output_tokens" => 2,
        "total_tokens" => 7,
        "prompt_cache_status" => "unknown",
      },
      result.usage
    )
    assert_operator FakeGovernor.acquire_calls.length, :>=, 1
    assert_operator FakeGovernor.renew_calls.length, :>=, 1
    assert_equal installation, FakeGovernor.acquire_calls.last.fetch(:installation)
    assert_equal "dev", FakeGovernor.acquire_calls.last.fetch(:provider_handle)
    assert_equal "lease-123", FakeGovernor.release_calls.last.fetch(:lease_token)
  end

  test "marks prompt cache details unsupported when the catalog metadata opts out" do
    installation = fresh_installation!
    ProviderEntitlement.create!(
      installation: installation,
      provider_handle: "dev",
      entitlement_key: "dev_window",
      window_kind: "rolling_five_hours",
      window_seconds: 5.hours.to_i,
      quota_limit: 200_000,
      active: true,
      metadata: {}
    )

    catalog_definition = test_provider_catalog_definition.deep_dup
    catalog_definition[:providers][:dev][:metadata] = {
      usage_capabilities: {
        prompt_cache_details: false,
      },
    }
    catalog_definition[:providers][:dev][:models]["mock-model"] = test_model_definition(
      display_name: "Mock Model",
      api_model: "mock-model",
      tokenizer_hint: "o200k_base",
      context_window_tokens: 100,
      max_output_tokens: 24,
      context_soft_limit_ratio: 0.5,
      request_defaults: {
        temperature: 0.7,
      }
    )
    catalog_definition[:model_roles]["conversation_title"] = ["dev/mock-model"]
    catalog = build_test_provider_catalog_from(catalog_definition)
    adapter = FlakyChatAdapter.new(
      response_body: {
        id: "chatcmpl-gateway-cache-unsupported-1",
        choices: [
          {
            message: {
              role: "assistant",
              content: "Draft release notes",
            },
            finish_reason: "stop",
          },
        ],
        usage: {
          prompt_tokens: 5,
          completion_tokens: 2,
          total_tokens: 7,
        },
      }
    )

    result = ProviderGateway::DispatchText.call(
      installation: installation,
      selector: "role:conversation_title",
      messages: [
        { "role" => "system", "content" => "Write a concise title." },
        { "role" => "user", "content" => "Draft release notes for the new retry flow." },
      ],
      max_output_tokens: 24,
      adapter: adapter,
      catalog: catalog,
      governor: FakeGovernor,
      lease_renew_interval_seconds: 0.01
    )

    assert_equal(
      {
        "input_tokens" => 5,
        "output_tokens" => 2,
        "total_tokens" => 7,
        "prompt_cache_status" => "unsupported",
      },
      result.usage
    )
  end

  test "refreshes expired oauth codex credentials before dispatch" do
    installation = fresh_installation!
    ProviderEntitlement.create!(
      installation: installation,
      provider_handle: "codex_subscription",
      entitlement_key: "shared_window",
      window_kind: "rolling_five_hours",
      window_seconds: 5.hours.to_i,
      quota_limit: 200_000,
      active: true,
      metadata: {}
    )
    ProviderCredential.create!(
      installation: installation,
      provider_handle: "codex_subscription",
      credential_kind: "oauth_codex",
      access_token: "expired-access-token",
      refresh_token: "refresh-token-1",
      expires_at: 5.minutes.ago,
      last_rotated_at: 1.hour.ago,
      metadata: {}
    )

    adapter = FlakyChatAdapter.new(
      response_body: {
        id: "chatcmpl-gateway-oauth-1",
        choices: [
          {
            message: {
              role: "assistant",
              content: "Draft release notes",
            },
            finish_reason: "stop",
          },
        ],
        usage: {
          prompt_tokens: 5,
          completion_tokens: 2,
          total_tokens: 7,
        },
      }
    )

    original_refresh = ProviderCredentials::RefreshOAuthCredential.method(:call)
    ProviderCredentials::RefreshOAuthCredential.singleton_class.define_method(:call) do |**kwargs|
      credential = kwargs.fetch(:credential)
      credential.update!(
        access_token: "fresh-access-token",
        refresh_token: "refresh-token-2",
        expires_at: 2.hours.from_now,
        last_refreshed_at: Time.current,
        refresh_failed_at: nil,
        refresh_failure_reason: nil
      )
      credential
    end

    ProviderGateway::DispatchText.call(
      installation: installation,
      selector: "candidate:codex_subscription/gpt-5.4",
      messages: [
        { "role" => "user", "content" => "Draft release notes for the new retry flow." },
      ],
      max_output_tokens: 24,
      adapter: adapter,
      governor: FakeGovernor,
      lease_renew_interval_seconds: 0.01
    )

    assert_equal "Bearer fresh-access-token", adapter.requests.last.dig(:headers, "Authorization")
  ensure
    ProviderCredentials::RefreshOAuthCredential.singleton_class.define_method(:call, original_refresh) if original_refresh
  end

  private

  def fresh_installation!
    delete_all_table_rows!
    create_installation!
  end
end
