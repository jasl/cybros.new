module WorkflowWaitTransitionTestSupport
  private

  def report_execution_started!(deployment:, mailbox_item:, agent_task_run:, occurred_at: Time.current)
    AgentControl::Poll.call(deployment: deployment, limit: 10, occurred_at: occurred_at)

    AgentControl::Report.call(
      deployment: deployment,
      method_id: "execution_started",
      protocol_message_id: "agent-start-#{next_test_sequence}",
      mailbox_item_id: mailbox_item.public_id,
      agent_task_run_id: agent_task_run.public_id,
      logical_work_id: agent_task_run.logical_work_id,
      attempt_no: agent_task_run.attempt_no,
      expected_duration_seconds: 30,
      occurred_at: occurred_at
    )
  end

  def report_execution_complete!(deployment:, mailbox_item:, agent_task_run:, terminal_payload:, occurred_at: Time.current)
    AgentControl::Report.call(
      deployment: deployment,
      method_id: "execution_complete",
      protocol_message_id: "agent-complete-#{next_test_sequence}",
      mailbox_item_id: mailbox_item.public_id,
      agent_task_run_id: agent_task_run.public_id,
      logical_work_id: agent_task_run.logical_work_id,
      attempt_no: agent_task_run.attempt_no,
      terminal_payload: terminal_payload,
      occurred_at: occurred_at
    )
  end

  def promote_subagent_runtime_context!(context, profile_catalog: default_profile_catalog)
    capability_snapshot = create_capability_snapshot!(
      agent_deployment: context.fetch(:deployment),
      version: 2,
      tool_catalog: default_tool_catalog("shell_exec", "subagent_spawn"),
      profile_catalog: profile_catalog,
      config_schema_snapshot: profile_aware_config_schema_snapshot,
      conversation_override_schema_snapshot: subagent_policy_override_schema_snapshot,
      default_config_snapshot: profile_aware_default_config_snapshot
    )

    context.fetch(:deployment).update!(active_capability_snapshot: capability_snapshot)
  end

  def human_task_wait_transition_payload(batch_id:, successor_node_key:, instructions:, node_key: "human_gate")
    {
      "wait_transition_requested" => {
        "batch_manifest" => {
          "batch_id" => batch_id,
          "resume_policy" => "re_enter_agent",
          "successor" => {
            "node_key" => successor_node_key,
            "node_type" => "turn_step",
          },
          "stages" => [
            {
              "stage_index" => 0,
              "dispatch_mode" => "serial",
              "completion_barrier" => "none",
              "intents" => [
                {
                  "intent_id" => "#{batch_id}:human",
                  "intent_kind" => "human_interaction_request",
                  "node_key" => node_key,
                  "node_type" => "human_interaction",
                  "requirement" => "required",
                  "conflict_scope" => "human_interaction",
                  "presentation_policy" => "user_projectable",
                  "durable_outcome" => "accepted",
                  "payload" => {
                    "request_type" => "HumanTaskRequest",
                    "blocking" => true,
                    "request_payload" => {
                      "instructions" => instructions,
                    },
                  },
                  "idempotency_key" => "#{batch_id}:human",
                },
              ],
            },
          ],
        },
      },
    }
  end

  def subagent_wait_all_transition_payload(batch_id:, successor_node_key:, intents:)
    {
      "wait_transition_requested" => {
        "batch_manifest" => {
          "batch_id" => batch_id,
          "resume_policy" => "re_enter_agent",
          "successor" => {
            "node_key" => successor_node_key,
            "node_type" => "turn_step",
          },
          "stages" => [
            {
              "stage_index" => 0,
              "dispatch_mode" => "parallel",
              "completion_barrier" => "wait_all",
              "intents" => intents.map.with_index do |intent, index|
                {
                  "intent_id" => "#{batch_id}:subagent:#{index}",
                  "intent_kind" => "subagent_spawn",
                  "node_key" => intent.fetch(:node_key),
                  "node_type" => "subagent_spawn",
                  "requirement" => intent.fetch(:requirement, "required"),
                  "conflict_scope" => "subagent_pool",
                  "presentation_policy" => "ops_trackable",
                  "durable_outcome" => "accepted",
                  "payload" => {
                    "content" => intent.fetch(:content),
                    "scope" => intent.fetch(:scope, "conversation"),
                    "profile_key" => intent[:profile_key],
                    "task_payload" => intent.fetch(:task_payload, {}),
                  }.compact,
                  "idempotency_key" => "#{batch_id}:subagent:#{index}",
                }
              end,
            },
          ],
        },
      },
    }
  end
end

ActiveSupport::TestCase.include(WorkflowWaitTransitionTestSupport)
ActionDispatch::IntegrationTest.include(WorkflowWaitTransitionTestSupport)
