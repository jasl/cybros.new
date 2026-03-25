require "test_helper"

class ProviderCatalogBootFlowTest < ActionDispatch::IntegrationTest
  test "the shipped provider catalog is boot-loadable and includes the default role entries" do
    catalog = ProviderCatalog::Load.call

    assert_equal "dev/mock-model", catalog.role_candidates("main").last
    assert_includes catalog.role_candidates("main"), "openrouter/openai-gpt-5.4"
    assert_equal ["codex_subscription/gpt-5.4", "openai/gpt-5.3-chat-latest"], catalog.role_candidates("coder").first(2)
    assert_equal ["openai/gpt-5.3-chat-latest"], catalog.role_candidates("planner")
  end
end
