class WorkflowWaitSnapshot
  DOCUMENT_KIND = "workflow_wait_snapshot".freeze

  def self.capture(workflow_run)
    return if workflow_run.blank?
    return if workflow_run.wait_state != "waiting"
    return if workflow_run.wait_reason_kind.in?(%w[agent_unavailable manual_recovery_required])

    new(workflow_run.wait_context_snapshot)
  end

  def self.from_workflow_run(workflow_run)
    return if workflow_run.blank?
    return if workflow_run.wait_snapshot_document.blank?

    new(workflow_run.wait_snapshot_document.payload)
  end

  def self.document_for_pause(workflow_run)
    return if workflow_run.blank?
    return workflow_run.wait_snapshot_document if workflow_run.wait_snapshot_document.present?

    snapshot = capture(workflow_run)
    return if snapshot.blank?

    JsonDocuments::Store.call(
      installation: workflow_run.installation,
      document_kind: DOCUMENT_KIND,
      payload: snapshot.to_h
    )
  end

  attr_reader :wait_reason_kind,
    :wait_policy_mode,
    :wait_retry_scope,
    :wait_resume_mode,
    :wait_failure_kind,
    :wait_retry_strategy,
    :wait_attempt_no,
    :wait_max_auto_retries,
    :wait_next_retry_at,
    :wait_last_error_summary,
    :blocking_resource_type,
    :blocking_resource_id

  def initialize(payload)
    normalized_payload = normalize_payload(payload)
    @wait_reason_kind = normalized_payload.fetch("wait_reason_kind")
    @wait_reason_payload = normalized_payload.fetch("wait_reason_payload")
    @wait_policy_mode = normalized_payload["wait_policy_mode"]
    @wait_retry_scope = normalized_payload["wait_retry_scope"]
    @wait_resume_mode = normalized_payload["wait_resume_mode"]
    @wait_failure_kind = normalized_payload["wait_failure_kind"]
    @wait_retry_strategy = normalized_payload["wait_retry_strategy"]
    @wait_attempt_no = normalized_payload["wait_attempt_no"]
    @wait_max_auto_retries = normalized_payload["wait_max_auto_retries"]
    @wait_next_retry_at = parse_time(normalized_payload["wait_next_retry_at"])
    @wait_last_error_summary = normalized_payload["wait_last_error_summary"]
    @waiting_since_at = parse_waiting_since(normalized_payload["waiting_since_at"])
    @blocking_resource_type = normalized_payload["blocking_resource_type"]
    @blocking_resource_id = normalized_payload["blocking_resource_id"]
  end

  def wait_reason_payload
    @wait_reason_payload.deep_dup
  end

  def waiting_since_at
    @waiting_since_at
  end

  def to_h
    {
      "wait_reason_kind" => wait_reason_kind,
      "wait_reason_payload" => wait_reason_payload,
      "wait_policy_mode" => wait_policy_mode,
      "wait_retry_scope" => wait_retry_scope,
      "wait_resume_mode" => wait_resume_mode,
      "wait_failure_kind" => wait_failure_kind,
      "wait_retry_strategy" => wait_retry_strategy,
      "wait_attempt_no" => wait_attempt_no,
      "wait_max_auto_retries" => wait_max_auto_retries,
      "wait_next_retry_at" => wait_next_retry_at&.iso8601,
      "wait_last_error_summary" => wait_last_error_summary,
      "waiting_since_at" => waiting_since_at&.iso8601,
      "blocking_resource_type" => blocking_resource_type,
      "blocking_resource_id" => blocking_resource_id,
    }.compact
  end

  def restore_attributes
    {
      "wait_state" => "waiting",
      "wait_reason_kind" => wait_reason_kind,
      "wait_reason_payload" => wait_reason_payload,
      "wait_policy_mode" => wait_policy_mode,
      "wait_retry_scope" => wait_retry_scope,
      "wait_resume_mode" => wait_resume_mode,
      "wait_failure_kind" => wait_failure_kind,
      "wait_retry_strategy" => wait_retry_strategy,
      "wait_attempt_no" => wait_attempt_no,
      "wait_max_auto_retries" => wait_max_auto_retries,
      "wait_next_retry_at" => wait_next_retry_at,
      "wait_last_error_summary" => wait_last_error_summary,
      "waiting_since_at" => waiting_since_at,
      "blocking_resource_type" => blocking_resource_type,
      "blocking_resource_id" => blocking_resource_id,
    }.compact
  end

  def resolved_for?(workflow_run)
    return true if wait_reason_kind.blank?

    case wait_reason_kind
    when "human_interaction"
      HumanInteractionRequest.where(
        workflow_run: workflow_run,
        public_id: blocking_resource_id,
        lifecycle_state: "open",
        blocking: true
      ).none?
    when "retryable_failure"
      retryable_failure_resolved_for?(workflow_run)
    when "external_dependency_blocked"
      blocked_workflow_node_resolved_for?(workflow_run)
    when "agent_request"
      blocked_workflow_node_resolved_for?(workflow_run)
    when "execution_runtime_request"
      blocked_workflow_node_resolved_for?(workflow_run)
    when "subagent_barrier"
      sessions = workflow_run.subagent_barrier_sessions
      return false if sessions.empty?

      sessions.none? { |session| !session.terminal_for_wait? }
    when "policy_gate"
      queued_turn_id = blocking_resource_id
      return true if queued_turn_id.blank?

      Turn.where(
        conversation: workflow_run.conversation,
        public_id: queued_turn_id,
        lifecycle_state: "queued"
      ).none?
    else
      false
    end
  end

  private

  def normalize_payload(payload)
    raise ArgumentError, "workflow wait snapshot must be a hash" unless payload.is_a?(Hash)

    payload.deep_stringify_keys.tap do |snapshot|
      snapshot["wait_reason_payload"] = snapshot.fetch("wait_reason_payload", {}).deep_stringify_keys
    end
  end

  def parse_waiting_since(value)
    parse_time(value)
  end

  def parse_time(value)
    return value if value.is_a?(ActiveSupport::TimeWithZone) || value.is_a?(Time)
    return if value.blank?

    Time.zone.parse(value)
  end

  def retryable_failure_resolved_for?(workflow_run)
    case blocking_resource_type
    when "AgentTaskRun"
      AgentTaskRun.where(
        workflow_run: workflow_run,
        public_id: blocking_resource_id,
        lifecycle_state: "failed"
      ).none?
    when "WorkflowNode"
      blocked_workflow_node_resolved_for?(workflow_run)
    else
      false
    end
  end

  def blocked_workflow_node_resolved_for?(workflow_run)
    blocked_node = WorkflowNode.find_by(
      workflow_run: workflow_run,
      public_id: blocking_resource_id
    )

    blocked_node.blank? || !blocked_node.waiting?
  end
end
