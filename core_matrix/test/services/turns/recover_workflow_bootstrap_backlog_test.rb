require "test_helper"

class Turns::RecoverWorkflowBootstrapBacklogTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "re-enqueues pending turns with no started timestamp" do
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
      Turns::RecoverWorkflowBootstrapBacklog.call
    end
  end

  test "re-enqueues stale materializing turns" do
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
    turn.update!(
      workflow_bootstrap_state: "materializing",
      workflow_bootstrap_started_at: 10.minutes.ago
    )
    clear_enqueued_jobs

    assert_enqueued_with(job: Turns::MaterializeAndDispatchJob, args: [turn.public_id]) do
      Turns::RecoverWorkflowBootstrapBacklog.call(stale_before: 5.minutes.ago)
    end
  end

  test "does not re-enqueue recent materializing turns" do
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
    turn.update!(
      workflow_bootstrap_state: "materializing",
      workflow_bootstrap_started_at: 1.minute.ago
    )
    clear_enqueued_jobs

    assert_no_enqueued_jobs do
      Turns::RecoverWorkflowBootstrapBacklog.call(stale_before: 5.minutes.ago)
    end
  end

  test "uses a fresh default stale cutoff on each call" do
    base_time = Time.zone.parse("2026-04-13 10:00:00")
    turn = nil

    travel_to(base_time) do
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
      turn.update!(
        workflow_bootstrap_state: "materializing",
        workflow_bootstrap_started_at: 4.minutes.ago
      )
      clear_enqueued_jobs
    end

    travel_to(base_time + 10.minutes) do
      assert_enqueued_with(job: Turns::MaterializeAndDispatchJob, args: [turn.public_id]) do
        Turns::RecoverWorkflowBootstrapBacklog.call
      end
    end
  end
end
