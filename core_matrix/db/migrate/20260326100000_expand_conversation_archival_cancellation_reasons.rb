class ExpandConversationArchivalCancellationReasons < ActiveRecord::Migration[8.2]
  def change
    remove_check_constraint :turns, name: "chk_turns_cancellation_reason_kind"
    add_check_constraint :turns,
      "(cancellation_reason_kind IS NULL OR cancellation_reason_kind IN ('conversation_deleted', 'conversation_archived'))",
      name: "chk_turns_cancellation_reason_kind"

    remove_check_constraint :workflow_runs, name: "chk_workflow_runs_cancellation_reason_kind"
    add_check_constraint :workflow_runs,
      "(cancellation_reason_kind IS NULL OR cancellation_reason_kind IN ('conversation_deleted', 'conversation_archived'))",
      name: "chk_workflow_runs_cancellation_reason_kind"
  end
end
