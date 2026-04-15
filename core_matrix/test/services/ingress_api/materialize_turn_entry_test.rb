require "test_helper"

class IngressAPI::MaterializeTurnEntryTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  InboundMessage = Struct.new(:public_id)

  test "creates a channel ingress turn and enqueues workflow plus title bootstrap" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])
    result = nil

    assert_enqueued_with(job: Turns::MaterializeAndDispatchJob) do
      assert_difference(["Turn.count", "Message.count"], +1) do
        result = IngressAPI::MaterializeTurnEntry.call(
          conversation: conversation,
          channel_inbound_message: InboundMessage.new("channel_inbound_message_1"),
          content: "Inbound request",
          origin_payload: {
            "ingress_binding_id" => "ingress_binding_1",
            "channel_session_id" => "channel_session_1",
            "channel_inbound_message_id" => "channel_inbound_message_1",
            "external_sender_id" => "telegram:user:42",
          },
          selector_source: "conversation",
          selector: "candidate:codex_subscription/gpt-5.3-codex"
        )
      end
    end

    title_job = enqueued_jobs.find { |job| job[:job].to_s == "Conversations::Metadata::BootstrapTitleJob" }
    assert title_job.present?
    assert_equal [conversation.public_id, result.turn.public_id], title_job[:args]
    assert_equal conversation, result.conversation
    assert_equal "Inbound request", result.message.content
    assert_equal result.turn.selected_input_message, result.message
  end

  test "can opt out of title bootstrap while still enqueuing workflow materialization" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])

    assert_enqueued_with(job: Turns::MaterializeAndDispatchJob) do
      IngressAPI::MaterializeTurnEntry.call(
        conversation: conversation,
        channel_inbound_message: InboundMessage.new("channel_inbound_message_2"),
        content: "Inbound request",
        origin_payload: {
          "ingress_binding_id" => "ingress_binding_1",
          "channel_session_id" => "channel_session_1",
          "channel_inbound_message_id" => "channel_inbound_message_2",
          "external_sender_id" => "telegram:user:42",
        },
        selector_source: "conversation",
        selector: "candidate:codex_subscription/gpt-5.3-codex",
        bootstrap_title: false
      )
    end

    title_jobs = enqueued_jobs.select { |job| job[:job].to_s == "Conversations::Metadata::BootstrapTitleJob" }
    assert_empty title_jobs
  end
end
