require "test_helper"

class AgentApiProcessRunsControllerTest < ActionDispatch::IntegrationTest
  test "execution runtime process run provisioning routes are removed" do
    assert_raises(ActionController::RoutingError) do
      Rails.application.routes.recognize_path("/execution_runtime_api/process_runs", method: :post)
    end
  end
end
