require "test_helper"

class RuntimeFeatures::InvokeTest < ActiveSupport::TestCase
  test "runtime_first uses runtime execution when capability is present" do
    context = create_workspace_context!
    context[:workspace].update!(
      config: {
        "features" => {
          "title_bootstrap" => {
            "strategy" => "runtime_first",
          },
        },
      }
    )
    agent_definition_version = create_agent_definition_version!(
      installation: context[:installation],
      agent: context[:agent],
      feature_contract: [
        {
          "feature_key" => "title_bootstrap",
          "execution_mode" => "direct",
          "lifecycle" => "live",
          "request_schema" => { "type" => "object" },
          "response_schema" => { "type" => "object" },
          "implementation_ref" => "fenix/title_bootstrap",
        },
      ]
    )
    context[:agent].agent_connections.update_all(
      lifecycle_state: "stale",
      updated_at: Time.current
    )
    create_agent_connection!(
      installation: context[:installation],
      agent: context[:agent],
      agent_definition_version: agent_definition_version
    )
    exchange = Struct.new(:requests) do
      def execute_feature(**kwargs)
        requests << kwargs
        {
          "status" => "ok",
          "result" => {
            "title" => "Runtime title",
          },
        }
      end
    end.new([])

    result = RuntimeFeatures::Invoke.call(
      feature_key: "title_bootstrap",
      workspace: context[:workspace],
      agent_definition_version: agent_definition_version,
      request_payload: {
        "message_content" => "Plan the launch checklist",
      },
      feature_request_exchange: exchange
    )

    assert_equal "ok", result.fetch("status")
    assert_equal "runtime", result.fetch("source")
    assert_equal "Runtime title", result.dig("result", "title")
    assert_equal 1, exchange.requests.length
  end

  test "embedded_only skips runtime execution entirely" do
    context = create_workspace_context!
    context[:workspace].update!(
      config: {
        "features" => {
          "title_bootstrap" => {
            "strategy" => "embedded_only",
          },
        },
      }
    )
    exchange = Struct.new(:called) do
      def execute_feature(**)
        self.called = true
      end
    end.new(false)

    original_call = EmbeddedFeatures::TitleBootstrap::Invoke.method(:call)
    EmbeddedFeatures::TitleBootstrap::Invoke.singleton_class.define_method(:call) do |**_kwargs|
      {
        "title" => "Embedded title",
      }
    end

    result = RuntimeFeatures::Invoke.call(
      feature_key: "title_bootstrap",
      workspace: context[:workspace],
      agent_definition_version: context[:agent_definition_version],
      request_payload: {
        "message_content" => "Plan the launch checklist",
      },
      feature_request_exchange: exchange
    )

    assert_equal "ok", result.fetch("status")
    assert_equal "embedded", result.fetch("source")
    assert_equal false, exchange.called
    assert_equal "Embedded title", result.dig("result", "title")
  ensure
    EmbeddedFeatures::TitleBootstrap::Invoke.singleton_class.define_method(:call, original_call) if original_call
  end

  test "runtime_required fails when capability is absent" do
    context = create_workspace_context!
    context[:workspace].update!(
      config: {
        "features" => {
          "title_bootstrap" => {
            "strategy" => "runtime_required",
          },
        },
      }
    )

    result = RuntimeFeatures::Invoke.call(
      feature_key: "title_bootstrap",
      workspace: context[:workspace],
      agent_definition_version: context[:agent_definition_version],
      request_payload: {
        "message_content" => "Plan the launch checklist",
      }
    )

    assert_equal "failed", result.fetch("status")
    assert_equal "runtime_feature_unavailable", result.fetch("code")
  end

  test "runtime_first falls back to embedded execution when runtime fails" do
    context = create_workspace_context!
    context[:workspace].update!(
      config: {
        "features" => {
          "title_bootstrap" => {
            "strategy" => "runtime_first",
          },
        },
      }
    )
    agent_definition_version = create_agent_definition_version!(
      installation: context[:installation],
      agent: context[:agent],
      feature_contract: [
        {
          "feature_key" => "title_bootstrap",
          "execution_mode" => "direct",
          "lifecycle" => "live",
          "request_schema" => { "type" => "object" },
          "response_schema" => { "type" => "object" },
          "implementation_ref" => "fenix/title_bootstrap",
        },
      ]
    )
    context[:agent].agent_connections.update_all(
      lifecycle_state: "stale",
      updated_at: Time.current
    )
    create_agent_connection!(
      installation: context[:installation],
      agent: context[:agent],
      agent_definition_version: agent_definition_version
    )
    exchange = Struct.new(:code) do
      def execute_feature(**)
        raise RuntimeFeatures::FeatureRequestExchange::RequestFailed.new(
          error_payload: {
            "code" => code,
            "message" => "runtime failed",
            "retryable" => false,
          }
        )
      end
    end.new("runtime_timeout")

    original_call = EmbeddedFeatures::TitleBootstrap::Invoke.method(:call)
    EmbeddedFeatures::TitleBootstrap::Invoke.singleton_class.define_method(:call) do |**_kwargs|
      {
        "title" => "Embedded fallback title",
      }
    end

    result = RuntimeFeatures::Invoke.call(
      feature_key: "title_bootstrap",
      workspace: context[:workspace],
      agent_definition_version: agent_definition_version,
      request_payload: {
        "message_content" => "Plan the launch checklist",
      },
      feature_request_exchange: exchange
    )

    assert_equal "ok", result.fetch("status")
    assert_equal "embedded", result.fetch("source")
    assert_equal true, result.fetch("fallback_used")
    assert_equal "runtime_timeout", result.fetch("runtime_failure_code")
    assert_equal "Embedded fallback title", result.dig("result", "title")
  ensure
    EmbeddedFeatures::TitleBootstrap::Invoke.singleton_class.define_method(:call, original_call) if original_call
  end
end
