require "test_helper"

class Conversations::CreateRootWeightTest < ActiveSupport::TestCase
  test "creates a root conversation within 13 SQL queries once capability authority is inlined" do
    context = create_workspace_context!

    created = nil
    assert_sql_query_count_at_most(13) do
      created = Conversations::CreateRoot.call(
        workspace: context[:workspace],
      )
    end

    assert_predicate created, :persisted?
  end
end
