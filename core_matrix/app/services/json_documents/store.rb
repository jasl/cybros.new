module JsonDocuments
  class Store
    def self.call(...)
      new(...).call
    end

    def initialize(installation:, document_kind:, payload:)
      @installation = installation
      @document_kind = document_kind
      @payload = normalize_payload(payload)
    end

    def call
      candidate = JsonDocument.new(
        installation: @installation,
        document_kind: @document_kind,
        payload: @payload
      )
      candidate.valid?

      JsonDocument.find_or_create_by!(
        installation: @installation,
        document_kind: @document_kind,
        content_sha256: candidate.content_sha256
      ) do |document|
        document.payload = candidate.payload
        document.content_bytesize = candidate.content_bytesize
      end
    end

    private

    def normalize_payload(payload)
      case payload
      when Hash
        payload.deep_stringify_keys
      when Array
        payload.map { |entry| entry.respond_to?(:deep_stringify_keys) ? entry.deep_stringify_keys : entry }
      else
        {}
      end
    end
  end
end
