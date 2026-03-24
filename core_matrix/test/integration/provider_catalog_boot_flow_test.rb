require "test_helper"

class ProviderCatalogBootFlowTest < ActionDispatch::IntegrationTest
  test "the shipped provider catalog is boot-loadable and includes the default role entries" do
    catalog = ProviderCatalog::Load.call

    assert_equal ["codex_subscription/gpt-5.4", "openai/gpt-5.3-chat-latest"], catalog.role_candidates("main")
    assert_equal ["codex_subscription/gpt-5.4", "openai/gpt-5.3-chat-latest"], catalog.role_candidates("coder")
    assert_equal ["openai/gpt-5.3-chat-latest"], catalog.role_candidates("planner")
  end
end
