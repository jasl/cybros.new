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
      capability_snapshot_id = @turn.agent_deployment.active_capability_snapshot_id
      raise_unavailable!("requires an active capability snapshot") if capability_snapshot_id.blank?

      unless @turn.agent_deployment.eligible_for_scheduling?
        raise_unavailable!("agent deployment is not eligible for future scheduling")
      end

      result = effective_catalog.resolve_selector(selector: raw_selector)

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
        "capability_snapshot_id" => capability_snapshot_id,
        "entitlement_key" => result.entitlement&.entitlement_key,
      }.compact
    end

    private

    def raw_selector
      return @selector if @selector.present?
      return "#{@turn.conversation.interactive_selector_provider_handle}/#{@turn.conversation.interactive_selector_model_ref}" if @turn.conversation.explicit_candidate?

      nil
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
