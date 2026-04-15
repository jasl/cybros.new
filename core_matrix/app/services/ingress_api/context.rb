module IngressAPI
  class Context
    attr_accessor :ingress_binding,
      :channel_connector,
      :channel_session,
      :conversation,
      :active_turn,
      :authorization_result,
      :coalesced_message_ids,
      :attachment_records,
      :media_digest,
      :dispatch_decision,
      :origin_payload,
      :envelope,
      :raw_payload,
      :request_metadata,
      :result,
      :command,
      :pipeline_trace

    def initialize(
      ingress_binding: nil,
      channel_connector: nil,
      channel_session: nil,
      conversation: nil,
      active_turn: nil,
      authorization_result: nil,
      coalesced_message_ids: [],
      attachment_records: [],
      media_digest: nil,
      dispatch_decision: nil,
      origin_payload: {},
      envelope: nil,
      raw_payload: nil,
      request_metadata: {},
      result: nil,
      command: nil,
      pipeline_trace: []
    )
      @ingress_binding = ingress_binding
      @channel_connector = channel_connector
      @channel_session = channel_session
      @conversation = conversation
      @active_turn = active_turn
      @authorization_result = authorization_result
      @coalesced_message_ids = coalesced_message_ids
      @attachment_records = attachment_records
      @media_digest = media_digest
      @dispatch_decision = dispatch_decision
      @origin_payload = origin_payload
      @envelope = envelope
      @raw_payload = raw_payload
      @request_metadata = request_metadata
      @result = result
      @command = command
      @pipeline_trace = pipeline_trace
    end

    def append_trace(step)
      @pipeline_trace << step
    end
  end
end
