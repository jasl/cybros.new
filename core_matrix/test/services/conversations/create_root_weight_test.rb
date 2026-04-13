require "test_helper"

class Conversations::CreateRootWeightTest < ActiveSupport::TestCase
  test "creates a root conversation within 8 SQL queries without full latest-anchor refresh" do
    context = create_workspace_context!

    created = nil
    assert_sql_query_count_at_most(8) do
      created = Conversations::CreateRoot.call(
        workspace: context[:workspace],
      )
    end

    assert_predicate created, :persisted?
  end
end
