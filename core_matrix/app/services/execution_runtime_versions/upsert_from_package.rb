require "digest"
require "json"

module ExecutionRuntimeVersions
  class UpsertFromPackage
    InvalidVersionPackage = Class.new(StandardError)

    REQUIRED_STRING_FIELDS = %w[
      execution_runtime_fingerprint
      kind
      protocol_version
      sdk_version
    ].freeze

    Result = Struct.new(:execution_runtime_version, :created, keyword_init: true)

    def self.call(...)
      new(...).call
    end

    def self.validate_package!(version_package)
      candidate = new(execution_runtime: ExecutionRuntime.new(installation: Installation.new(name: "validation", bootstrap_state: "bootstrapped", global_settings: {})), version_package: version_package)
      candidate.send(:validate_version_package!)
    end

    def initialize(execution_runtime:, version_package:)
      @execution_runtime = execution_runtime
      @version_package = normalize_hash(version_package)
    end

    def call
      validate_version_package!

      content_fingerprint = Digest::SHA256.hexdigest(JSON.generate(@version_package))
      with_existing_or_create(content_fingerprint)
    rescue ActiveRecord::RecordNotUnique
      existing = find_existing_version(content_fingerprint)
      raise if existing.blank?

      Result.new(execution_runtime_version: existing, created: false)
    end

    private

    def with_existing_or_create(content_fingerprint)
      @execution_runtime.with_lock do
        existing = find_existing_version(content_fingerprint)
        return Result.new(execution_runtime_version: existing, created: false) if existing.present?

        execution_runtime_version = ExecutionRuntimeVersion.create!(
          installation: @execution_runtime.installation,
          execution_runtime: @execution_runtime,
          version: @execution_runtime.execution_runtime_versions.maximum(:version).to_i + 1,
          content_fingerprint: content_fingerprint,
          execution_runtime_fingerprint: @version_package.fetch("execution_runtime_fingerprint"),
          kind: @version_package.fetch("kind"),
          protocol_version: @version_package.fetch("protocol_version"),
          sdk_version: @version_package.fetch("sdk_version"),
          capability_payload_document: find_or_create_document("execution_runtime_capability_payload", @version_package.fetch("capability_payload", {})),
          tool_catalog_document: find_or_create_document("execution_runtime_tool_catalog", @version_package.fetch("tool_catalog", [])),
          reflected_host_metadata_document: find_or_create_document("reflected_host_metadata", @version_package.fetch("reflected_host_metadata", {}))
        )

        Result.new(execution_runtime_version: execution_runtime_version, created: true)
      end
    end

    def find_existing_version(content_fingerprint)
      ExecutionRuntimeVersion.find_by(
        execution_runtime: @execution_runtime,
        content_fingerprint: content_fingerprint
      )
    end

    def validate_version_package!
      unless @version_package.is_a?(Hash)
        raise InvalidVersionPackage, "Version package must be a Hash"
      end

      errors = []

      REQUIRED_STRING_FIELDS.each do |field|
        value = @version_package[field]
        errors << "Version package #{field} must be a non-empty String" unless value.is_a?(String) && value.present?
      end

      errors << "Version package capability_payload must be a Hash" unless @version_package["capability_payload"].is_a?(Hash)
      errors << "Version package tool_catalog must be an Array" unless @version_package["tool_catalog"].is_a?(Array)

      reflected_host_metadata = @version_package["reflected_host_metadata"]
      if reflected_host_metadata.present? && !reflected_host_metadata.is_a?(Hash)
        errors << "Version package reflected_host_metadata must be a Hash"
      end

      raise InvalidVersionPackage, errors.join(", ") if errors.any?
    end

    def find_or_create_document(document_kind, payload)
      serialized_payload = JSON.generate(payload)
      content_sha256 = Digest::SHA256.hexdigest(serialized_payload)

      JsonDocument.find_or_create_by!(
        installation: @execution_runtime.installation,
        document_kind: document_kind,
        content_sha256: content_sha256
      ) do |document|
        document.payload = payload
        document.content_bytesize = serialized_payload.bytesize
      end
    end

    def normalize_hash(value)
      return {} if value.blank?
      return value.deep_stringify_keys if value.is_a?(Hash)

      value
    end
  end
end
