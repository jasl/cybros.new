require "test_helper"

class ProcessCloseEscalationE2ETest < ActionDispatch::IntegrationTest
  test "execution-plane close reports from a program version on the wrong execution runtime are stale" do
    context = build_agent_control_context!
    correct_harness = FakeAgentRuntimeHarness.new(
      test_case: self,
      deployment: context[:deployment],
      machine_credential: context[:machine_credential],
      execution_machine_credential: context[:execution_machine_credential]
    )
    other_agent_program = create_agent_program!(installation: context[:installation])
    other_execution_runtime = create_execution_runtime!(installation: context[:installation])
    wrong_registration = register_agent_runtime!(
      installation: context[:installation],
      actor: context[:actor],
      agent_program: other_agent_program,
      execution_runtime: other_execution_runtime,
      reuse_enrollment: true
    )
    wrong_deployment = wrong_registration.fetch(:deployment)
    wrong_registration.fetch(:agent_session).update!(
      health_status: "healthy",
      last_heartbeat_at: Time.current,
      last_health_check_at: Time.current
    )
    wrong_harness = FakeAgentRuntimeHarness.new(
      test_case: self,
      deployment: wrong_deployment,
      machine_credential: wrong_registration.fetch(:machine_credential),
      execution_machine_credential: wrong_registration.fetch(:execution_machine_credential)
    )
    process_run = create_process_run!(
      workflow_node: context[:workflow_node],
      execution_runtime: context[:execution_runtime],
      kind: "background_service",
      timeout_seconds: nil
    )
    Leases::Acquire.call(
      leased_resource: process_run,
      holder_key: context[:execution_session].public_id,
      heartbeat_timeout_seconds: 30
    )

    close_request = MailboxScenarioBuilder.new(self).close_request!(
      context: context,
      resource: process_run
    ).fetch(:mailbox_item)
    correct_harness.poll!

    wrong_result = wrong_harness.report!(
      method_id: "resource_closed",
      protocol_message_id: "wrong-env-close-#{next_test_sequence}",
      mailbox_item_id: close_request.public_id,
      close_request_id: close_request.public_id,
      resource_type: "ProcessRun",
      resource_id: process_run.public_id,
      close_outcome_kind: "forced",
      close_outcome_payload: { "source" => "wrong-environment" }
    )

    assert_equal 404, wrong_result.fetch("http_status")
    assert_equal "Couldn't find ProcessRun", wrong_result.fetch("error")
    assert_equal "requested", process_run.reload.close_state
  end

  test "background service supports graceful close" do
    process_run = interrupt_process_run!(close_outcome_kind: "graceful")

    assert process_run.reload.stopped?
    assert_equal "graceful", process_run.close_outcome_kind
  end

  test "poll escalates a background-service close request to forced after the grace deadline elapses" do
    context, harness, process_run, occurred_at = interrupt_process_run_context!

    initial_delivery = travel_to(occurred_at) do
      harness.poll!.fetch("mailbox_items").find do |mailbox_item|
        mailbox_item.fetch("payload").fetch("resource_id") == process_run.public_id
      end
    end
    escalated_delivery = travel_to(occurred_at + 31.seconds) do
      harness.poll!.fetch("mailbox_items").find do |mailbox_item|
        mailbox_item.fetch("payload").fetch("resource_id") == process_run.public_id
      end
    end

    assert_equal "graceful", initial_delivery.dig("payload", "strictness")
    assert_equal "forced", escalated_delivery.dig("payload", "strictness")
    assert_equal "requested", process_run.reload.close_state
  end

  test "background service supports forced close after graceful escalation" do
    process_run = interrupt_process_run!(close_outcome_kind: "forced")

    assert process_run.reload.stopped?
    assert_equal "forced", process_run.close_outcome_kind
  end

  test "force deadline expiration records timed_out_forced without a terminal close report" do
    _context, harness, process_run, occurred_at = interrupt_process_run_context!

    close_request = travel_to(occurred_at) do
      AgentControlMailboxItem.find_by!(
        item_type: "resource_close_request",
        target_execution_runtime: process_run.execution_runtime
      )
    end

    travel_to(occurred_at + 61.seconds) do
      harness.poll!
    end

    assert process_run.reload.lost?
    assert process_run.close_failed?
    assert_equal "timed_out_forced", process_run.close_outcome_kind
    assert_equal "completed", close_request.reload.status
  end

  test "background service records residual abandonment when forced close still fails" do
    process_run = interrupt_process_run!(close_outcome_kind: "residual_abandoned")

    assert process_run.reload.lost?
    assert_equal "residual_abandoned", process_run.close_outcome_kind
  end

  private

  def interrupt_process_run!(close_outcome_kind:)
    _context, harness, process_run, occurred_at = interrupt_process_run_context!

    close_request = travel_to(occurred_at) do
      harness.poll!.fetch("mailbox_items").find { |mailbox_item| mailbox_item.fetch("payload").fetch("resource_id") == process_run.public_id }
    end

    travel_to(occurred_at) do
      harness.report!(
        method_id: "resource_closed",
        protocol_message_id: "close-#{next_test_sequence}",
        mailbox_item_id: close_request.fetch("item_id"),
        close_request_id: close_request.fetch("item_id"),
        resource_type: "ProcessRun",
        resource_id: process_run.public_id,
        close_outcome_kind: close_outcome_kind,
        close_outcome_payload: { "source" => "e2e" }
      )
    end

    process_run
  end

  def interrupt_process_run_context!
    context = build_agent_control_context!
    harness = FakeAgentRuntimeHarness.new(
      test_case: self,
      deployment: context[:deployment],
      machine_credential: context[:machine_credential],
      execution_machine_credential: context[:execution_machine_credential]
    )
    process_run = create_process_run!(
      workflow_node: context[:workflow_node],
      execution_runtime: context[:execution_runtime],
      kind: "background_service",
      timeout_seconds: nil
    )
    Leases::Acquire.call(
      leased_resource: process_run,
      holder_key: context[:execution_session].public_id,
      heartbeat_timeout_seconds: 30
    )
    occurred_at = Time.zone.parse("2026-03-26 15:00:00 UTC")

    travel_to(occurred_at) do
      MailboxScenarioBuilder.new(self).close_request!(
        context: context,
        resource: process_run
      )
    end

    [context, harness, process_run, occurred_at]
  end
end
