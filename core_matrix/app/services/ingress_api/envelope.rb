module IngressAPI
  class Envelope
    ATTRIBUTES = %i[
      platform
      driver
      ingress_binding_public_id
      channel_connector_public_id
      external_event_key
      external_message_key
      peer_kind
      peer_id
      thread_key
      external_sender_id
      sender_snapshot
      text
      attachments
      reply_to_external_message_key
      quoted_external_message_key
      quoted_text
      quoted_sender_label
      quoted_attachment_refs
      occurred_at
      transport_metadata
      raw_payload
    ].freeze

    attr_reader(*ATTRIBUTES)

    def initialize(**attributes)
      ATTRIBUTES.each do |attribute|
        instance_variable_set(:"@#{attribute}", attributes.fetch(attribute))
      end
    end
  end
end
