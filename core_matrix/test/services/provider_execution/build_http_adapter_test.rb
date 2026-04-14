require "test_helper"

class ProviderExecution::BuildHttpAdapterTest < ActiveSupport::TestCase
  test "builds the pooled httpx adapter for configured real provider keys" do
    %w[
      anthropic_messages
      codex_subscription_responses
      gemini_generate_content
      openai_responses
      openrouter_chat_completions
      local_openai_compatible_chat_completions
    ].each do |adapter_key|
      adapter = ProviderExecution::BuildHttpAdapter.call(provider_definition: { adapter_key: adapter_key })

      assert_instance_of SimpleInference::HTTPAdapters::HTTPX, adapter
    end
  end

  test "builds the default adapter for mock provider keys" do
    %w[mock_llm_chat_completions mock_llm_responses].each do |adapter_key|
      adapter = ProviderExecution::BuildHttpAdapter.call(provider_definition: { adapter_key: adapter_key })

      assert_instance_of SimpleInference::HTTPAdapters::Default, adapter
    end
  end

  test "builds the httpx adapter for explicit httpx provider keys" do
    %w[httpx_chat_completions httpx_responses].each do |adapter_key|
      adapter = ProviderExecution::BuildHttpAdapter.call(provider_definition: { adapter_key: adapter_key })

      assert_instance_of SimpleInference::HTTPAdapters::HTTPX, adapter
    end
  end

  test "raises for an unknown provider adapter key" do
    error = assert_raises(ArgumentError) do
      ProviderExecution::BuildHttpAdapter.call(provider_definition: { adapter_key: "mystery_adapter" })
    end

    assert_includes error.message, "unsupported provider adapter key"
  end
end
