require "test_helper"

class Conversations::CreationSupportTest < ActiveSupport::TestCase
  CreationSupportHarness = Class.new do
    include Conversations::CreationSupport

    public :build_child_conversation
    public :create_lineage_store_reference_for!
    public :refresh_child_conversation_from_parent!
  end

  test "raises when the parent is missing its lineage store reference" do
    context = create_workspace_context!
    parent = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      agent_program: context[:agent_program]
    )
    parent.lineage_store_reference.delete
    parent.association(:lineage_store_reference).reset
    harness = CreationSupportHarness.new
    child = harness.build_child_conversation(parent: parent, kind: "fork")

    error = assert_raises(ActiveRecord::RecordNotFound) do
      harness.create_lineage_store_reference_for!(child, parent: parent)
    end

    assert_equal "lineage store reference is missing", error.message
  end

  test "refreshes stale child attributes from the current parent state" do
    parent_context = create_workspace_context!
    parent = Conversations::CreateRoot.call(
      workspace: parent_context[:workspace],
      agent_program: parent_context[:agent_program]
    )
    alternate_agent_program = create_agent_program!(installation: parent_context[:installation])
    alternate_workspace = create_workspace!(
      installation: parent_context[:installation],
      user: parent_context[:user],
      user_program_binding: parent_context[:user_program_binding],
      name: "Alternate Workspace #{next_test_sequence}"
    )
    harness = CreationSupportHarness.new
    child = harness.build_child_conversation(parent: parent, kind: "fork")
    child.workspace = alternate_workspace
    child.agent_program = alternate_agent_program
    child.purpose = "automation"
    child.lifecycle_state = "archived"

    refreshed = harness.refresh_child_conversation_from_parent!(conversation: child, parent: parent)

    assert_same child, refreshed
    assert_equal parent.installation, refreshed.installation
    assert_equal parent.workspace, refreshed.workspace
    assert_equal parent.agent_program, refreshed.agent_program
    assert_equal parent, refreshed.parent_conversation
    assert_equal parent.purpose, refreshed.purpose
    assert refreshed.active?
  end
end
