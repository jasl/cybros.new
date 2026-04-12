module AppSurface
  module Presenters
    class LLMProviderPresenter
      def self.call(...)
        new(...).call
      end

      def initialize(effective_catalog:, provider_handle:, provider_definition:, policy: nil, credential: nil, entitlements: [], connection_check: nil)
        @effective_catalog = effective_catalog
        @provider_handle = provider_handle.to_s
        @provider_definition = provider_definition.deep_stringify_keys
        @policy = policy
        @credential = credential
        @entitlements = entitlements
        @connection_check = connection_check
      end

      def call
        {
          "provider_handle" => @provider_handle,
          "display_name" => @provider_definition.fetch("display_name"),
          "catalog_enabled" => @provider_definition.fetch("enabled"),
          "enabled" => policy_enabled?,
          "effective_enabled" => effective_enabled?,
          "requires_credential" => @provider_definition.fetch("requires_credential"),
          "credential_kind" => @provider_definition["credential_kind"],
          "configured" => configured?,
          "usable" => usable?,
          "reauthorization_required" => @credential&.reauthorization_required? || false,
          "credential_status" => credential_status,
          "models_count" => @provider_definition.fetch("models").size,
          "credential" => credential_payload,
          "policy" => policy_payload,
          "entitlements" => entitlement_payloads,
          "connection_test" => connection_test_payload,
        }.compact
      end

      private

      def policy_enabled?
        return true if @policy.nil?

        @policy.enabled
      end

      def effective_enabled?
        @provider_definition.fetch("enabled") && policy_enabled?
      end

      def configured?
        return true unless @provider_definition.fetch("requires_credential")

        @credential.present?
      end

      def usable?
        return false unless effective_enabled?

        @provider_definition.fetch("models").keys.any? do |model_ref|
          @effective_catalog.availability(provider_handle: @provider_handle, model_ref: model_ref).usable?
        end
      end

      def credential_status
        return "not_required" unless @provider_definition.fetch("requires_credential")
        return "missing" if @credential.blank?
        return "reauthorization_required" if @credential.reauthorization_required?

        "configured"
      end

      def credential_payload
        {
          "configured" => @credential.present?,
          "kind" => @provider_definition["credential_kind"],
          "metadata" => @credential&.metadata || {},
          "last_rotated_at" => @credential&.last_rotated_at&.iso8601(6),
          "last_refreshed_at" => @credential&.last_refreshed_at&.iso8601(6),
          "expires_at" => @credential&.expires_at&.iso8601(6),
          "refresh_failed_at" => @credential&.refresh_failed_at&.iso8601(6),
          "refresh_failure_reason" => @credential&.refresh_failure_reason,
        }.compact
      end

      def policy_payload
        {
          "enabled" => policy_enabled?,
          "selection_defaults" => @policy&.selection_defaults || {},
        }
      end

      def entitlement_payloads
        @entitlements.sort_by(&:entitlement_key).map do |entitlement|
          {
            "entitlement_key" => entitlement.entitlement_key,
            "window_kind" => entitlement.window_kind,
            "quota_limit" => entitlement.quota_limit,
            "active" => entitlement.active,
            "metadata" => entitlement.metadata,
          }
        end
      end

      def connection_test_payload
        return { "status" => "never_requested" } if @connection_check.blank?

        {
          "connection_test_id" => @connection_check.public_id,
          "status" => @connection_check.lifecycle_state,
          "queued_at" => @connection_check.queued_at&.iso8601(6),
          "started_at" => @connection_check.started_at&.iso8601(6),
          "finished_at" => @connection_check.finished_at&.iso8601(6),
          "request" => @connection_check.request_payload,
          "result" => @connection_check.result_payload.presence,
          "failure" => @connection_check.failure_payload.presence,
        }.compact
      end
    end
  end
end
