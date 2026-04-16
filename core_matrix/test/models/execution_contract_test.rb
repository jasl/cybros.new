require "test_helper"

class ExecutionContractTest < ActiveSupport::TestCase
  test "belongs to a frozen workspace agent global instructions document" do
    association = ExecutionContract.reflect_on_association(:workspace_agent_global_instructions_document)

    assert_equal :belongs_to, association&.macro
    assert_equal "JsonDocument", association&.class_name
    assert_equal true, association&.options&.fetch(:optional, false)
  end

  test "belongs to a frozen workspace agent profile settings document" do
    association = ExecutionContract.reflect_on_association(:workspace_agent_profile_settings_document)

    assert_equal :belongs_to, association&.macro
    assert_equal "JsonDocument", association&.class_name
    assert_equal true, association&.options&.fetch(:optional, false)
  end

  test "reads frozen workspace agent global instructions from the document payload" do
    context = build_agent_control_context!
    document = create_json_document!(
      installation: context[:installation],
      document_kind: "workspace_agent_global_instructions",
      payload: { "global_instructions" => "Use concise Chinese.\n" }
    )

    execution_contract = context.fetch(:turn).execution_contract
    execution_contract.update!(workspace_agent_global_instructions_document: document)

    assert_equal "Use concise Chinese.\n", execution_contract.workspace_agent_global_instructions
  end

  test "rejects workspace agent global instructions documents with the wrong document kind" do
    context = build_agent_control_context!
    document = create_json_document!(
      installation: context[:installation],
      document_kind: "execution_tool_surface",
      payload: { "global_instructions" => "Use concise Chinese.\n" }
    )

    execution_contract = context.fetch(:turn).execution_contract
    execution_contract.workspace_agent_global_instructions_document = document

    assert_not execution_contract.valid?
    assert_includes execution_contract.errors[:workspace_agent_global_instructions_document], "must have document kind workspace_agent_global_instructions"
  end

  test "reads frozen workspace agent profile settings from the document payload" do
    context = build_agent_control_context!
    document = create_json_document!(
      installation: context[:installation],
      document_kind: "workspace_agent_profile_settings",
      payload: {
        "profile_settings" => {
          "interactive_profile_key" => "main",
          "default_subagent_profile_key" => "researcher",
        },
      }
    )

    execution_contract = context.fetch(:turn).execution_contract
    execution_contract.update!(workspace_agent_profile_settings_document: document)

    assert_equal(
      {
        "interactive_profile_key" => "main",
        "default_subagent_profile_key" => "researcher",
      },
      execution_contract.workspace_agent_profile_settings
    )
  end
end
