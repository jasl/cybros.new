require "test_helper"

class ProviderCatalog::LoadTest < ActiveSupport::TestCase
  test "loads the shipped provider catalog and exposes provider models and role candidates" do
    catalog = ProviderCatalog::Load.call

    assert_equal %w[codex_subscription openai], catalog.providers.keys.sort
    assert_equal ["codex_subscription/gpt-5.4", "openai/gpt-5.3-chat-latest"], catalog.role_candidates("main")
    assert_equal ["codex_subscription/gpt-5.4", "openai/gpt-5.3-chat-latest"], catalog.role_candidates("coder")

    openai_model = catalog.model("openai", "gpt-5.3-chat-latest")

    assert_equal "GPT-5.3 Chat Latest", openai_model.fetch(:display_name)
    assert_equal 272_000, openai_model.fetch(:context_window_tokens)
    assert_equal true, openai_model.dig(:capabilities, :multimodal_inputs, :image)
    assert_equal false, openai_model.dig(:capabilities, :multimodal_inputs, :audio)
    assert_equal false, openai_model.dig(:capabilities, :multimodal_inputs, :video)
    assert_equal true, openai_model.dig(:capabilities, :multimodal_inputs, :file)
  end

  test "raises a descriptive error when the catalog file is missing" do
    error = assert_raises(ProviderCatalog::Load::MissingCatalog) do
      ProviderCatalog::Load.call(path: Rails.root.join("config/providers/missing.yml"))
    end

    assert_includes error.message, "config/providers/missing.yml"
  end
end
