require "test_helper"

class ProviderCatalog::LoadTest < ActiveSupport::TestCase
  test "defaults to the llm catalog path" do
    assert_equal Rails.root.join("config/llm_catalog.yml"), ProviderCatalog::Load::DEFAULT_PATH
  end

  test "loads the shipped provider catalog and exposes provider models and role candidates" do
    catalog = ProviderCatalog::Load.call

    assert_equal %w[codex_subscription dev llama_cpp ollama openai openrouter], catalog.providers.keys.sort
    assert_equal "api_key", catalog.provider("openai").fetch(:credential_kind)
    assert_equal "api_key", catalog.provider("openrouter").fetch(:credential_kind)
    assert_equal "oauth_codex", catalog.provider("codex_subscription").fetch(:credential_kind)
    assert_equal %w[development test], catalog.provider("dev").fetch(:environments)
    assert_equal "dev/mock-model", catalog.role_candidates("main").last

    openai_model = catalog.model("openai", "gpt-5.3-chat-latest")

    assert_equal "GPT-5.3 Chat Latest", openai_model.fetch(:display_name)
    assert_equal "gpt-5.3-chat-latest", openai_model.fetch(:api_model)
    assert_equal "o200k_base", openai_model.fetch(:tokenizer_hint)
    assert_equal 272_000, openai_model.fetch(:context_window_tokens)
    assert_equal true, openai_model.dig(:capabilities, :multimodal_inputs, :image)
    assert_equal false, openai_model.dig(:capabilities, :multimodal_inputs, :audio)
    assert_equal false, openai_model.dig(:capabilities, :multimodal_inputs, :video)
    assert_equal true, openai_model.dig(:capabilities, :multimodal_inputs, :file)
  end

  test "merges config.d overrides in base then env order" do
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "config"))
      FileUtils.mkdir_p(File.join(dir, "config.d"))

      File.write(File.join(dir, "config", "llm_catalog.yml"), <<~YAML)
        version: 1
        providers:
          openai:
            display_name: OpenAI
            enabled: true
            environments:
              - development
              - test
              - production
            adapter_key: openai_responses
            base_url: https://api.openai.com/v1
            headers: {}
            wire_api: responses
            transport: https
            responses_path: /responses
            requires_credential: true
            credential_kind: api_key
            metadata:
              source: base
            models:
              gpt-5.3-chat-latest:
                display_name: GPT-5.3 Chat Latest
                api_model: gpt-5.3-chat-latest
                tokenizer_hint: o200k_base
                context_window_tokens: 272000
                max_output_tokens: 128000
                context_soft_limit_ratio: 0.8
                request_defaults: {}
                metadata:
                  release_channel: stable
                capabilities:
                  text_output: true
                  tool_calls: true
                  structured_output: true
                  multimodal_inputs:
                    image: true
                    audio: false
                    video: false
                    file: true
        model_roles:
          main:
            - openai/gpt-5.3-chat-latest
      YAML

      File.write(File.join(dir, "config.d", "llm_catalog.yml"), <<~YAML)
        providers:
          openai:
            metadata:
              source: config_d_base
      YAML

      File.write(File.join(dir, "config.d", "llm_catalog.test.yml"), <<~YAML)
        providers:
          openai:
            metadata:
              source: config_d_env
      YAML

      catalog = ProviderCatalog::Load.call(
        path: File.join(dir, "config", "llm_catalog.yml"),
        override_dir: File.join(dir, "config.d"),
        env: "test"
      )

      assert_equal "config_d_env", catalog.provider("openai").dig(:metadata, :source)
    end
  end

  test "raises a descriptive error when the catalog file is missing" do
    error = assert_raises(ProviderCatalog::Load::MissingCatalog) do
      ProviderCatalog::Load.call(path: Rails.root.join("config/missing_llm_catalog.yml"))
    end

    assert_includes error.message, "config/missing_llm_catalog.yml"
  end
end
