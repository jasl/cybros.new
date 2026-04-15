module Workflows
  class ResolveModelSelector
    def self.call(...)
      new(...).call
    end

    def initialize(turn:, selector_source:, selector: nil)
      @turn = turn
      @selector_source = selector_source.to_s
      @selector = selector&.to_s
    end

    def call
      result = resolve_selector_result

      unless result.usable?
        return raise_unavailable!("unknown model role #{result.normalized_selector.delete_prefix("role:")}") if result.reason_key == "unknown_model_role"
        return raise_unavailable!("explicit candidate is unavailable") if result.reason_key == "reservation_denied" && effective_catalog.candidate_selector?(result.normalized_selector)
        return raise_unavailable!("explicit candidate is unavailable: #{result.reason_key}") if effective_catalog.candidate_selector?(result.normalized_selector)

        raise_unavailable!("no candidate available for #{result.normalized_selector}")
      end

      {
        "selector_source" => @selector_source,
        "normalized_selector" => result.normalized_selector,
        "resolved_role_name" => result.resolved_role_name,
        "resolved_provider_handle" => result.provider_handle,
        "resolved_model_ref" => result.model_ref,
        "resolution_reason" => result.resolution_reason,
        "fallback_count" => result.fallback_count,
        "agent_definition_version_id" => @turn.agent_definition_version.public_id,
        "entitlement_key" => result.entitlement&.entitlement_key,
      }.compact
    end

    private

    def resolve_selector_result
      return effective_catalog.resolve_selector(selector: raw_selector) if raw_selector.present?

      if apply_mount_interactive_profile_selector?
        result = effective_catalog.resolve_selector(selector: mount_interactive_profile_selector)
        return result if result.usable?
      end

      effective_catalog.resolve_selector(selector: nil)
    end

    def raw_selector
      return @selector if @selector.present?
      return "#{@turn.conversation.interactive_selector_provider_handle}/#{@turn.conversation.interactive_selector_model_ref}" if @turn.conversation.explicit_candidate?

      nil
    end

    def mount_interactive_profile_selector
      profile_key = @turn.conversation.workspace_agent&.interactive_profile_key_override
      return if profile_key.blank?

      "role:#{profile_key}"
    end

    def apply_mount_interactive_profile_selector?
      @selector_source == "conversation" && mount_interactive_profile_selector.present?
    end

    def effective_catalog
      @effective_catalog ||= ProviderCatalog::EffectiveCatalog.new(installation: @turn.installation, env: Rails.env)
    end

    def raise_unavailable!(message)
      @turn.errors.add(:resolved_model_selection_snapshot, message)
      raise ActiveRecord::RecordInvalid, @turn
    end
  end
end
