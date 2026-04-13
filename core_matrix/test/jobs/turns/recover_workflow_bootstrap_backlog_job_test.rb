require "test_helper"

class Turns::RecoverWorkflowBootstrapBacklogJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "re-enqueues backlog turns through the maintenance job" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      agent: context[:agent]
    )
    turn = Turns::AcceptPendingUserTurn.call(
      conversation: conversation,
      content: "Follow up",
      selector_source: "app_api",
      selector: "candidate:codex_subscription/gpt-5.3-codex"
    )
    clear_enqueued_jobs

    assert_enqueued_with(job: Turns::MaterializeAndDispatchJob, args: [turn.public_id]) do
      Turns::RecoverWorkflowBootstrapBacklogJob.perform_now
    end
  end
end
