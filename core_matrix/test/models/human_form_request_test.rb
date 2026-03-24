require "test_helper"

class HumanFormRequestTest < ActiveSupport::TestCase
  test "requires structured schema and defaults hashes" do
    context = build_human_interaction_context!

    request = HumanFormRequest.new(
      installation: context[:installation],
      workflow_run: context[:workflow_run],
      workflow_node: context[:workflow_node],
      conversation: context[:conversation],
      turn: context[:turn],
      lifecycle_state: "open",
      blocking: true,
      request_payload: {
        "input_schema" => { "required" => ["ticket_id"] },
        "defaults" => { "priority" => "high" },
      },
      result_payload: {}
    )

    assert request.valid?

    invalid_schema = request.dup
    invalid_schema.request_payload = {
      "input_schema" => "bad",
      "defaults" => [],
    }

    assert_not invalid_schema.valid?
    assert_includes invalid_schema.errors[:request_payload], "must include an input_schema hash"
    assert_includes invalid_schema.errors[:request_payload], "must include a defaults hash when defaults are present"
  end
end
