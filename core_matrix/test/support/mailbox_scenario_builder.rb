class MailboxScenarioBuilder
  def initialize(test_case)
    @test_case = test_case
  end

  def execution_assignment!(context:, task_payload: { "step" => "execute" }, **attrs)
    agent_task_run = @test_case.send(
      :create_agent_task_run!,
      workflow_node: context.fetch(:workflow_node),
      task_payload: task_payload,
      **attrs
    )
    mailbox_item = AgentControl::CreateExecutionAssignment.call(
      agent_task_run: agent_task_run,
      payload: { "task_payload" => task_payload },
      dispatch_deadline_at: 5.minutes.from_now,
      execution_hard_deadline_at: 10.minutes.from_now
    )

    {
      agent_task_run: agent_task_run,
      mailbox_item: mailbox_item,
    }
  end

  def close_request!(context:, resource:, request_kind: "turn_interrupt", reason_kind: "operator_stop", strictness: "graceful")
    mailbox_item = AgentControl::CreateResourceCloseRequest.call(
      resource: resource,
      request_kind: request_kind,
      reason_kind: reason_kind,
      strictness: strictness,
      grace_deadline_at: 30.seconds.from_now,
      force_deadline_at: 60.seconds.from_now
    )

    {
      resource: resource,
      mailbox_item: mailbox_item,
    }
  end

  def agent_request!(context:, request_kind:, payload:, logical_work_id:, attempt_no: 1)
    mailbox_item = AgentControl::CreateAgentRequest.call(
      agent_snapshot: context.fetch(:agent_snapshot),
      request_kind: request_kind,
      payload: payload,
      logical_work_id: logical_work_id,
      attempt_no: attempt_no,
      dispatch_deadline_at: 5.minutes.from_now
    )

    {
      mailbox_item: mailbox_item,
    }
  end
end
