module WorkflowWaitTransitionTestSupport
  private

  def report_execution_started!(agent_definition_version:, mailbox_item:, agent_task_run:, occurred_at: Time.current)
    dispatch_execution_report!(
      agent_definition_version: agent_definition_version,
      mailbox_item: mailbox_item,
      agent_task_run: agent_task_run,
      method_id: "execution_started",
      protocol_message_id: "agent-start-#{next_test_sequence}",
      expected_duration_seconds: 30,
      occurred_at: occurred_at
    )
  end

  def report_execution_complete!(agent_definition_version:, mailbox_item:, agent_task_run:, terminal_payload:, occurred_at: Time.current)
    dispatch_execution_report!(
      agent_definition_version: agent_definition_version,
      mailbox_item: mailbox_item,
      agent_task_run: agent_task_run,
      method_id: "execution_complete",
      protocol_message_id: "agent-complete-#{next_test_sequence}",
      terminal_payload: terminal_payload,
      occurred_at: occurred_at
    )
  end

  def promote_subagent_runtime_context!(context, profile_policy: default_profile_policy)
    capability_snapshot = create_compatible_agent_definition_version!(
      agent_definition_version: context.fetch(:agent_definition_version),
      version: 2,
      tool_contract: default_tool_catalog("exec_command", "subagent_spawn"),
      profile_policy: profile_policy,
      canonical_config_schema: profile_aware_canonical_config_schema,
      conversation_override_schema: subagent_policy_conversation_override_schema,
      default_canonical_config: profile_aware_default_canonical_config
    )

    adopt_agent_definition_version!(context, capability_snapshot)
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

  def dispatch_execution_report!(agent_definition_version:, mailbox_item:, agent_task_run:, method_id:, protocol_message_id:, occurred_at:, **payload)
    if mailbox_item.execution_runtime_plane?
      execution_runtime_connection = mailbox_item.target_execution_runtime&.active_execution_runtime_connection ||
        mailbox_item.target_execution_runtime&.execution_runtime_connections&.order(created_at: :desc)&.first

      raise "execution runtime connection is required for runtime-plane reports" if execution_runtime_connection.blank?

      AgentControl::Poll.call(
        execution_runtime_connection: execution_runtime_connection,
        limit: 10,
        occurred_at: occurred_at
      ) if method_id == "execution_started"

      AgentControl::Report.call(
        agent_definition_version: agent_definition_version,
        execution_runtime_connection: execution_runtime_connection,
        method_id: method_id,
        protocol_message_id: protocol_message_id,
        mailbox_item_id: mailbox_item.public_id,
        agent_task_run_id: agent_task_run.public_id,
        logical_work_id: agent_task_run.logical_work_id,
        attempt_no: agent_task_run.attempt_no,
        occurred_at: occurred_at,
        **payload
      )
    else
      AgentControl::Poll.call(agent_definition_version: agent_definition_version, limit: 10, occurred_at: occurred_at) if method_id == "execution_started"

      AgentControl::Report.call(
        agent_definition_version: agent_definition_version,
        method_id: method_id,
        protocol_message_id: protocol_message_id,
        mailbox_item_id: mailbox_item.public_id,
        agent_task_run_id: agent_task_run.public_id,
        logical_work_id: agent_task_run.logical_work_id,
        attempt_no: agent_task_run.attempt_no,
        occurred_at: occurred_at,
        **payload
      )
    end
  end
end

ActiveSupport::TestCase.include(WorkflowWaitTransitionTestSupport)
ActionDispatch::IntegrationTest.include(WorkflowWaitTransitionTestSupport)
