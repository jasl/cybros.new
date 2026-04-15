require "test_helper"

module Workbench
end

class Workbench::CreateConversationFromAgentTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "creates a conversation from an explicit workspace agent mount" do
    context = prepare_workflow_execution_setup!(create_workspace_context!)

    result = nil

    assert_enqueued_with(job: Turns::MaterializeAndDispatchJob) do
      assert_no_difference(["Workspace.count", "WorkspaceAgent.count"]) do
        assert_difference(["Conversation.count", "Turn.count", "Message.count"], +1) do
          assert_no_difference("WorkflowRun.count") do
            result = Workbench::CreateConversationFromAgent.call(
              user: context[:user],
              workspace_agent: context[:workspace_agent],
              content: "Help me start",
              selector: "candidate:codex_subscription/gpt-5.3-codex"
            )
          end
        end
      end
    end

    title_job = enqueued_jobs.find { |job| job[:job].to_s == "Conversations::Metadata::BootstrapTitleJob" }
    assert title_job.present?
    assert_equal [result.conversation.public_id, result.turn.public_id], title_job[:args]

    assert_equal context[:workspace], result.workspace
    assert_equal context[:workspace_agent], result.conversation.workspace_agent
    assert_equal context[:agent], result.conversation.agent
    assert_equal "Help me start", result.message.content
    assert_equal result.conversation, result.turn.conversation
    assert_equal "pending", result.turn.workflow_bootstrap_state
    assert_equal "candidate:codex_subscription/gpt-5.3-codex", result.turn.workflow_bootstrap_payload.fetch("selector")
    assert_equal I18n.t("conversations.defaults.untitled_title"), result.conversation.reload.title
    assert result.conversation.title_source_none?
    refute_respond_to result, :workflow_run
  end

  test "allows overriding the execution runtime for the first turn" do
    context = prepare_workflow_execution_setup!(create_workspace_context!)
    default_runtime = context[:execution_runtime]
    override_runtime = create_execution_runtime!(installation: context[:installation])
    create_execution_runtime_connection!(installation: context[:installation], execution_runtime: override_runtime)

    result = nil

    assert_enqueued_with(job: Turns::MaterializeAndDispatchJob) do
      result = Workbench::CreateConversationFromAgent.call(
        user: context[:user],
        workspace_agent: context[:workspace_agent],
        content: "Use the other runtime",
        selector: "candidate:codex_subscription/gpt-5.3-codex",
        execution_runtime: override_runtime
      )
    end

    title_job = enqueued_jobs.find { |job| job[:job].to_s == "Conversations::Metadata::BootstrapTitleJob" }
    assert title_job.present?
    assert_equal [result.conversation.public_id, result.turn.public_id], title_job[:args]

    assert_equal override_runtime, result.turn.execution_runtime
    assert_equal default_runtime, result.workspace.default_execution_runtime
    assert_equal context[:workspace_agent], result.conversation.workspace_agent
    assert_equal "pending", result.turn.workflow_bootstrap_state
    assert_equal I18n.t("conversations.defaults.untitled_title"), result.conversation.reload.title
    assert result.conversation.title_source_none?
  end
end
