require "test_helper"

class MockLLMModelsTest < ActionDispatch::IntegrationTest
  test "returns the dev provider models from the loaded catalog" do
    get "/mock_llm/v1/models"

    assert_response :success
    assert_equal "list", response.parsed_body["object"]

    model_ids = response.parsed_body.fetch("data").map { |entry| entry.fetch("id") }.sort
    expected_ids = ProviderCatalog::Load.call.provider("dev").fetch(:models).keys.sort

    assert_equal expected_ids, model_ids
  end
end
