require "digest"
require "json"

module AgentDefinitionVersions
  class UpsertFromPackage
    InvalidDefinitionPackage = Class.new(StandardError)

    REQUIRED_STRING_FIELDS = %w[
      program_manifest_fingerprint
      prompt_pack_ref
      prompt_pack_fingerprint
      protocol_version
      sdk_version
    ].freeze

    REQUIRED_HASH_FIELDS = %w[
      profile_policy
      canonical_config_schema
      conversation_override_schema
      default_canonical_config
      reflected_surface
    ].freeze

    REQUIRED_ARRAY_FIELDS = %w[
      protocol_methods
      tool_contract
    ].freeze

    Result = Struct.new(:agent_definition_version, :created, keyword_init: true)

    def self.call(...)
      new(...).call
    end

    def self.validate_package!(definition_package)
      candidate = allocate
      candidate.instance_variable_set(:@definition_package, definition_package.is_a?(Hash) ? definition_package.deep_stringify_keys : definition_package)
      candidate.send(:validate_definition_package!)
    end

    def initialize(agent:, definition_package:)
      @agent = agent
      @definition_package = normalize_hash(definition_package)
    end

    def call
      validate_definition_package!

      definition_fingerprint = Digest::SHA256.hexdigest(JSON.generate(@definition_package))
      with_existing_or_create(definition_fingerprint)
    rescue ActiveRecord::RecordNotUnique
      existing = find_existing_definition_version(definition_fingerprint)
      raise if existing.blank?

      Result.new(agent_definition_version: existing, created: false)
    end

    private

    def with_existing_or_create(definition_fingerprint)
      @agent.with_lock do
        existing = find_existing_definition_version(definition_fingerprint)
        return Result.new(agent_definition_version: existing, created: false) if existing.present?

        agent_definition_version = AgentDefinitionVersion.create!(
          installation: @agent.installation,
          agent: @agent,
          version: @agent.agent_definition_versions.maximum(:version).to_i + 1,
          definition_fingerprint: definition_fingerprint,
          program_manifest_fingerprint: @definition_package.fetch("program_manifest_fingerprint"),
          prompt_pack_ref: @definition_package.fetch("prompt_pack_ref"),
          prompt_pack_fingerprint: @definition_package.fetch("prompt_pack_fingerprint"),
          protocol_version: @definition_package.fetch("protocol_version"),
          sdk_version: @definition_package.fetch("sdk_version"),
          protocol_methods_document: find_or_create_document("agent_protocol_methods", @definition_package.fetch("protocol_methods", [])),
          feature_contract_document: find_or_create_document("agent_feature_contract", @definition_package.fetch("feature_contract", [])),
          tool_contract_document: find_or_create_document("agent_tool_contract", @definition_package.fetch("tool_contract", [])),
          profile_policy_document: find_or_create_document("agent_profile_policy", @definition_package.fetch("profile_policy", {})),
          canonical_config_schema_document: find_or_create_document("canonical_config_schema", @definition_package.fetch("canonical_config_schema", {})),
          conversation_override_schema_document: find_or_create_document("conversation_override_schema", @definition_package.fetch("conversation_override_schema", {})),
          default_canonical_config_document: find_or_create_document("default_canonical_config", @definition_package.fetch("default_canonical_config", {})),
          reflected_surface_document: find_or_create_document("reflected_surface", @definition_package.fetch("reflected_surface", {}))
        )

        Result.new(agent_definition_version: agent_definition_version, created: true)
      end
    end

    def find_existing_definition_version(definition_fingerprint)
      AgentDefinitionVersion.find_by(agent: @agent, definition_fingerprint: definition_fingerprint)
    end

    def validate_definition_package!
      unless @definition_package.is_a?(Hash)
        raise InvalidDefinitionPackage, "Definition package must be a Hash"
      end

      errors = []

      REQUIRED_STRING_FIELDS.each do |field|
        value = @definition_package[field]
        errors << "Definition package #{field} must be a non-empty String" unless value.is_a?(String) && value.present?
      end

      REQUIRED_HASH_FIELDS.each do |field|
        errors << "Definition package #{field} must be a Hash" unless @definition_package[field].is_a?(Hash)
      end

      REQUIRED_ARRAY_FIELDS.each do |field|
        errors << "Definition package #{field} must be an Array" unless @definition_package[field].is_a?(Array)
      end

      raise InvalidDefinitionPackage, errors.join(", ") if errors.any?
    end

    def find_or_create_document(document_kind, payload)
      serialized_payload = JSON.generate(payload)
      content_sha256 = Digest::SHA256.hexdigest(serialized_payload)

      JsonDocument.find_or_create_by!(
        installation: @agent.installation,
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
