require "test_helper"

class Conversations::DependencyBlockersQueryTest < ActiveSupport::TestCase
  test "reports dependency blockers and blocked status" do
    context = build_canonical_variable_context!
    root = context[:conversation]
    anchor_message_id = context[:turn].selected_input_message_id

    Conversations::CreateThread.call(parent: root, historical_anchor_message_id: anchor_message_id)
    importer = Conversations::CreateThread.call(parent: root, historical_anchor_message_id: anchor_message_id)
    Conversations::AddImport.call(
      conversation: importer,
      kind: "quoted_context",
      source_message: context[:turn].selected_input_message
    )
    CanonicalVariable.create!(
      installation: context[:installation],
      workspace: context[:workspace],
      scope: "workspace",
      key: "customer_name",
      typed_value_payload: { "type" => "string", "value" => "Acme" },
      writer: context[:user],
      source_kind: "manual_user",
      source_conversation: root,
      source_turn: context[:turn],
      source_workflow_run: context[:workflow_run],
      projection_policy: "silent",
      current: true
    )

    result = Conversations::DependencyBlockersQuery.call(conversation: root)
    snapshot = Conversations::BlockerSnapshotQuery.call(conversation: root)

    assert_equal(
      {
        descendant_lineage_blockers: 2,
        root_store_blocker: true,
        variable_provenance_blocker: true,
        import_provenance_blocker: true,
      },
      result.to_h
    )
    assert_equal snapshot.dependency_blockers.to_h, result.to_h
    assert result.blocked?
  end

  test "returns a clear result when the conversation has no dependency blockers" do
    context = build_canonical_variable_context!
    thread = Conversations::CreateThread.call(
      parent: context[:conversation],
      historical_anchor_message_id: context[:turn].selected_input_message_id
    )

    result = Conversations::DependencyBlockersQuery.call(conversation: thread)
    snapshot = Conversations::BlockerSnapshotQuery.call(conversation: thread)

    assert_equal(
      {
        descendant_lineage_blockers: 0,
        root_store_blocker: false,
        variable_provenance_blocker: false,
        import_provenance_blocker: false,
      },
      result.to_h
    )
    assert_equal snapshot.dependency_blockers.to_h, result.to_h
    assert_not result.blocked?
  end
end
