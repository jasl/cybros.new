module IngressAPI
  class Result
    attr_reader :status,
      :handled_via,
      :trace,
      :envelope,
      :conversation,
      :channel_session,
      :command_name,
      :request_metadata,
      :rejection_reason,
      :payload

    def self.ready_for_turn_entry(**attributes)
      new(status: "ready_for_turn_entry", **attributes)
    end

    def self.duplicate(**attributes)
      new(status: "duplicate", **attributes)
    end

    def self.handled(handled_via:, **attributes)
      new(status: "handled", handled_via: handled_via, **attributes)
    end

    def self.rejected(rejection_reason:, **attributes)
      new(status: "rejected", rejection_reason: rejection_reason, **attributes)
    end

    def initialize(status:, handled_via: nil, trace: [], envelope: nil, conversation: nil, channel_session: nil, command_name: nil, request_metadata: {}, rejection_reason: nil, payload: {})
      @status = status
      @handled_via = handled_via
      @trace = trace
      @envelope = envelope
      @conversation = conversation
      @channel_session = channel_session
      @command_name = command_name
      @request_metadata = request_metadata
      @rejection_reason = rejection_reason
      @payload = payload
    end

    def duplicate?
      status == "duplicate"
    end

    def handled?
      status == "handled"
    end

    def rejected?
      status == "rejected"
    end
  end
end
