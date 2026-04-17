require "test_helper"

class AgentApiCommandRunsControllerTest < ActionDispatch::IntegrationTest
  test "execution runtime command run provisioning routes are removed" do
    assert_raises(ActionController::RoutingError) do
      Rails.application.routes.recognize_path("/execution_runtime_api/command_runs", method: :post)
    end

    assert_raises(ActionController::RoutingError) do
      Rails.application.routes.recognize_path("/execution_runtime_api/command_runs/cmd_123/activate", method: :post)
    end
  end
end
