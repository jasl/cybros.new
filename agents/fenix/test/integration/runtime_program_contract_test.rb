require "test_helper"

class RuntimeProgramContractTest < ActionDispatch::IntegrationTest
  test "prepare round returns the frozen contract shape" do
    post "/runtime/rounds/prepare", params: shared_contract_fixture("core_matrix_fenix_prepare_round_v1"), as: :json

    assert_response :success

    body = JSON.parse(response.body)

    assert_equal shared_contract_fixture("fenix_prepare_round_response_v1"), normalize_prepare_round_response(body)
  end

  test "execute program tool returns the frozen contract shape" do
    post "/runtime/program_tools/execute", params: shared_contract_fixture("core_matrix_fenix_execute_program_tool_v1"), as: :json

    assert_response :success

    body = JSON.parse(response.body)

    assert_equal shared_contract_fixture("fenix_execute_program_tool_response_v1"), body
  end

  test "execute program tool rejects tools outside the visible program surface" do
    payload = shared_contract_fixture("core_matrix_fenix_execute_program_tool_v1")
    payload["agent_context"]["allowed_tool_names"] = ["compact_context"]

    post "/runtime/program_tools/execute", params: payload, as: :json

    assert_response :unprocessable_entity

    body = JSON.parse(response.body)

    assert_equal "failed", body.fetch("status")
    assert_equal "tool_not_allowed", body.dig("error", "code")
  end

  private

  def normalize_prepare_round_response(body)
    {
      "message_roles" => body.fetch("messages").map { |entry| entry.fetch("role") },
      "likely_model" => body.fetch("likely_model"),
      "program_tool_names" => body.fetch("program_tools").map { |entry| entry.fetch("tool_name") },
      "trace_hooks" => body.fetch("trace").map { |entry| entry.fetch("hook") },
    }
  end
end
