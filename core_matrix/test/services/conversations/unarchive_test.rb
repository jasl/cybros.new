require "test_helper"

class Conversations::UnarchiveTest < ActiveSupport::TestCase
  test "returns an archived conversation to active state" do
    root = Conversations::CreateRoot.call(workspace: create_workspace_context![:workspace])
    archived = Conversations::Archive.call(conversation: root)

    restored = Conversations::Unarchive.call(conversation: archived)

    assert restored.active?
    assert_equal root.id, restored.id
  end
end
