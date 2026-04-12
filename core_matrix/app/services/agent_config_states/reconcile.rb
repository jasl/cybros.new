require "digest"
require "json"

module AgentConfigStates
  class Reconcile
    def self.call(...)
      new(...).call
    end

    def initialize(agent:, agent_definition_version:)
      @agent = agent
      @agent_definition_version = agent_definition_version
    end

    def call
      state = @agent.agent_config_state
      effective_payload = resolved_effective_payload(state)
      if state.present? &&
         state.base_agent_definition_version_id == @agent_definition_version.id &&
         state.effective_payload == effective_payload &&
         state.reconciliation_ready?
        return state
      end

      effective_document = find_or_create_document(
        installation: @agent.installation,
        document_kind: "effective_canonical_config",
        payload: effective_payload
      )
      content_fingerprint = Digest::SHA256.hexdigest(JSON.generate(effective_payload))

      if state.present?
        updates = {
          base_agent_definition_version: @agent_definition_version,
          effective_document: effective_document,
          content_fingerprint: content_fingerprint,
          reconciliation_state: "ready",
        }

        if state.base_agent_definition_version_id != @agent_definition_version.id ||
           state.content_fingerprint != content_fingerprint
          updates[:version] = state.version + 1
        end

        state.update!(updates)
        return state
      end

      AgentConfigState.create!(
        installation: @agent.installation,
        agent: @agent,
        base_agent_definition_version: @agent_definition_version,
        override_document: nil,
        effective_document: effective_document,
        content_fingerprint: content_fingerprint,
        reconciliation_state: "ready",
        version: 1
      )
    end

    private

    def resolved_effective_payload(state)
      base_payload = @agent_definition_version.default_canonical_config.deep_dup
      override_payload = state&.override_payload || {}
      return base_payload if override_payload.blank?

      base_payload.deep_merge(override_payload)
    end

    def find_or_create_document(installation:, document_kind:, payload:)
      serialized_payload = JSON.generate(payload)
      content_sha256 = Digest::SHA256.hexdigest(serialized_payload)

      JsonDocument.find_or_create_by!(
        installation: installation,
        document_kind: document_kind,
        content_sha256: content_sha256
      ) do |document|
        document.payload = payload
        document.content_bytesize = serialized_payload.bytesize
      end
    end
  end
end
