require "securerandom"

module AgentControl
  class CreateAgentProgramRequest
    REQUEST_KINDS = %w[prepare_round execute_program_tool].freeze

    def self.call(...)
      new(...).call
    end

    def initialize(agent_program_version:, request_kind:, payload:, logical_work_id:, attempt_no: 1, dispatch_deadline_at:, execution_hard_deadline_at: nil, protocol_message_id: nil, causation_id: nil, lease_timeout_seconds: 30, priority: 1)
      @agent_program_version = agent_program_version
      @request_kind = request_kind.to_s
      @payload = payload.deep_stringify_keys
      @logical_work_id = logical_work_id
      @attempt_no = attempt_no.to_i
      @dispatch_deadline_at = dispatch_deadline_at
      @execution_hard_deadline_at = execution_hard_deadline_at
      @protocol_message_id = protocol_message_id || "kernel-program-request-#{SecureRandom.uuid}"
      @causation_id = causation_id
      @lease_timeout_seconds = lease_timeout_seconds
      @priority = priority
    end

    def call
      raise ArgumentError, "unsupported request kind #{@request_kind}" unless REQUEST_KINDS.include?(@request_kind)

      mailbox_item = AgentControlMailboxItem.create!(
        installation: @agent_program_version.installation,
        target_agent_program: @agent_program_version.agent_program,
        target_agent_program_version: @agent_program_version,
        item_type: "agent_program_request",
        runtime_plane: "program",
        target_kind: "agent_program_version",
        target_ref: @agent_program_version.public_id,
        logical_work_id: @logical_work_id,
        attempt_no: @attempt_no,
        protocol_message_id: @protocol_message_id,
        causation_id: @causation_id,
        priority: @priority,
        status: "queued",
        available_at: Time.current,
        dispatch_deadline_at: @dispatch_deadline_at,
        lease_timeout_seconds: @lease_timeout_seconds,
        execution_hard_deadline_at: @execution_hard_deadline_at,
        payload: request_payload
      )

      PublishPending.call(mailbox_item: mailbox_item)
      mailbox_item
    end

    private

    def request_payload
      @payload.merge("request_kind" => @request_kind)
    end
  end
end
