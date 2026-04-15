module IngressAPI
  module TransportAdapter
    def verify_request!(raw_payload:, request_metadata:)
      raise NotImplementedError
    end

    def normalize_envelope(raw_payload:, ingress_binding:, channel_connector:, request_metadata:)
      raise NotImplementedError
    end

    def download_attachment(...)
      raise NotImplementedError
    end

    def send_delivery(...)
      raise NotImplementedError
    end
  end
end
