require "test_helper"

module TurnTodoPlans
  class BuildFeedChangesetTest < ActiveSupport::TestCase
    test "builds canonical feed entries from old and new plan snapshots" do
      changeset = TurnTodoPlans::BuildFeedChangeset.call(
        previous_plan: {
          "goal_summary" => "Replace legacy plan paths",
          "current_item_key" => "define-domain",
          "items" => [
            {
              "item_key" => "define-domain",
              "title" => "Define new plan",
              "status" => "in_progress",
              "position" => 0,
            },
          ],
        },
        current_plan: {
          "goal_summary" => "Replace legacy plan paths",
          "current_item_key" => "wire-supervision",
          "items" => [
            {
              "item_key" => "define-domain",
              "title" => "Define new plan",
              "status" => "completed",
              "position" => 0,
            },
            {
              "item_key" => "wire-supervision",
              "title" => "Wire supervision",
              "status" => "in_progress",
              "position" => 1,
            },
          ],
        },
        occurred_at: Time.current
      )

      assert_equal %w[turn_todo_item_completed turn_todo_item_started], changeset.map { |entry| entry.fetch("event_kind") }
      assert_equal ["Define new plan completed.", "Started wire supervision."], changeset.map { |entry| entry.fetch("summary") }
    end
  end
end
