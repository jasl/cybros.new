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
      agent: context[:agent]
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
      agent: parent_context[:agent]
    )
    alternate_agent = create_agent!(installation: parent_context[:installation])
    alternate_workspace = create_workspace!(
      installation: parent_context[:installation],
      user: parent_context[:user],
      agent: parent_context[:agent],
      name: "Alternate Workspace #{next_test_sequence}"
    )
    harness = CreationSupportHarness.new
    child = harness.build_child_conversation(parent: parent, kind: "fork")
    child.workspace = alternate_workspace
    child.agent = alternate_agent
    child.purpose = "automation"
    child.lifecycle_state = "archived"

    refreshed = harness.refresh_child_conversation_from_parent!(conversation: child, parent: parent)

    assert_same child, refreshed
    assert_equal parent.installation, refreshed.installation
    assert_equal parent.workspace, refreshed.workspace
    assert_equal parent.agent, refreshed.agent
    assert_equal parent, refreshed.parent_conversation
    assert_equal parent.purpose, refreshed.purpose
    assert refreshed.active?
  end

  test "builds child conversations with copied runtime and no current epoch" do
    context = create_workspace_context!
    parent = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      agent: context[:agent]
    )
    harness = CreationSupportHarness.new

    child = harness.build_child_conversation(parent: parent, kind: "fork")
    assert child.valid?

    assert_equal parent.current_execution_runtime, child.current_execution_runtime
    assert_nil child.current_execution_epoch
    assert_equal "not_started", child.execution_continuity_state
  end
end
