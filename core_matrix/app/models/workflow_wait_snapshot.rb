class WorkflowWaitSnapshot
  SNAPSHOT_KEY = "paused_wait_snapshot".freeze

  def self.capture(workflow_run)
    return if workflow_run.blank?
    return if workflow_run.wait_state != "waiting"
    return if workflow_run.wait_reason_kind.in?(%w[agent_unavailable manual_recovery_required])

    new(
      "wait_reason_kind" => workflow_run.wait_reason_kind,
      "wait_reason_payload" => workflow_run.wait_reason_payload,
      "waiting_since_at" => workflow_run.waiting_since_at,
      "blocking_resource_type" => workflow_run.blocking_resource_type,
      "blocking_resource_id" => workflow_run.blocking_resource_id
    )
  end

  def self.from_workflow_run(workflow_run)
    return if workflow_run.blank?

    snapshot = workflow_run.wait_reason_payload[SNAPSHOT_KEY]
    return if snapshot.blank?

    new(snapshot)
  end

  attr_reader :wait_reason_kind, :blocking_resource_type, :blocking_resource_id

  def initialize(payload)
    normalized_payload = normalize_payload(payload)
    @wait_reason_kind = normalized_payload.fetch("wait_reason_kind")
    @wait_reason_payload = normalized_payload.fetch("wait_reason_payload")
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
      AgentTaskRun.where(
        workflow_run: workflow_run,
        public_id: blocking_resource_id,
        lifecycle_state: "failed"
      ).none?
    when "subagent_barrier"
      subagent_session_ids = Array(wait_reason_payload["subagent_session_ids"]).map(&:to_s)
      return true if subagent_session_ids.empty?

      sessions = SubagentSession.where(
        owner_conversation: workflow_run.conversation,
        public_id: subagent_session_ids
      ).to_a

      return false unless sessions.size == subagent_session_ids.size

      sessions.none? { |session| !session.terminal_for_wait? }
    when "policy_gate"
      queued_turn_id = wait_reason_payload["queued_turn_id"]
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
    return value if value.is_a?(ActiveSupport::TimeWithZone) || value.is_a?(Time)
    return if value.blank?

    Time.zone.parse(value)
  end
end
