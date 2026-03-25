require "test_helper"

class Conversations::UnarchiveTest < ActiveSupport::TestCase
  test "returns an archived conversation to active state" do
    root = Conversations::CreateRoot.call(workspace: create_workspace_context![:workspace])
    archived = Conversations::Archive.call(conversation: root)

    restored = Conversations::Unarchive.call(conversation: archived)

    assert restored.active?
    assert_equal root.id, restored.id
  end

  test "rejects unarchiving a non-archived conversation" do
    root = Conversations::CreateRoot.call(workspace: create_workspace_context![:workspace])

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Conversations::Unarchive.call(conversation: root)
    end

    assert_includes error.record.errors[:lifecycle_state], "must be archived before unarchival"
  end

  test "rejects unarchiving non-retained conversations" do
    root = Conversations::CreateRoot.call(workspace: create_workspace_context![:workspace])
    root.update!(lifecycle_state: "archived", deletion_state: "pending_delete", deleted_at: Time.current)

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Conversations::Unarchive.call(conversation: root)
    end

    assert_includes error.record.errors[:deletion_state], "must be retained before unarchival"
  end
end
