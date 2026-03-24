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

      normalized_selector = normalize_selector
      resolved_role_name, candidates = expand_candidates(normalized_selector)
      fallback_count = 0
      last_fallback_reason = nil

      candidates.each do |candidate_ref|
        provider_handle, model_ref = candidate_ref.split("/", 2)
        entitlement = active_entitlement(provider_handle)

        unless candidate_available?(provider_handle, model_ref, entitlement)
          last_fallback_reason = "role_fallback_after_filter"
          return raise_unavailable!("explicit candidate is unavailable") if explicit_candidate_selector?(normalized_selector)

          fallback_count += 1
          next
        end

        if reservation_denied?(entitlement)
          last_fallback_reason = "role_fallback_after_reservation"
          return raise_unavailable!("explicit candidate is unavailable") if explicit_candidate_selector?(normalized_selector)

          fallback_count += 1
          next
        end

        return {
          "selector_source" => @selector_source,
          "normalized_selector" => normalized_selector,
          "resolved_role_name" => resolved_role_name,
          "resolved_provider_handle" => provider_handle,
          "resolved_model_ref" => model_ref,
          "resolution_reason" => resolution_reason(normalized_selector, fallback_count, last_fallback_reason),
          "fallback_count" => fallback_count,
          "capability_snapshot_id" => capability_snapshot_id,
          "entitlement_key" => entitlement&.entitlement_key,
        }.compact
      end

      raise_unavailable!("no candidate available for #{normalized_selector}")
    end

    private

    def normalize_selector
      return normalize_explicit_selector(@selector) if @selector.present?

      if @turn.conversation.explicit_candidate?
        return "candidate:#{@turn.conversation.interactive_selector_provider_handle}/#{@turn.conversation.interactive_selector_model_ref}"
      end

      "role:main"
    end

    def normalize_explicit_selector(selector)
      return selector if selector.start_with?("role:", "candidate:")
      return "candidate:#{selector}" if selector.include?("/")

      "role:#{selector}"
    end

    def expand_candidates(normalized_selector)
      if explicit_candidate_selector?(normalized_selector)
        return [nil, [normalized_selector.delete_prefix("candidate:")]]
      end

      role_name = normalized_selector.delete_prefix("role:")
      [role_name, catalog.role_candidates(role_name)]
    rescue KeyError
      raise_unavailable!("unknown model role #{role_name}")
    end

    def candidate_available?(provider_handle, model_ref, entitlement)
      policy_enabled?(provider_handle) &&
        model_exists?(provider_handle, model_ref) &&
        entitlement.present?
    end

    def policy_enabled?(provider_handle)
      ProviderPolicy.find_by(installation: @turn.installation, provider_handle: provider_handle)&.enabled != false
    end

    def model_exists?(provider_handle, model_ref)
      catalog.model(provider_handle, model_ref)
      true
    rescue KeyError
      false
    end

    def active_entitlement(provider_handle)
      ProviderEntitlement.where(
        installation: @turn.installation,
        provider_handle: provider_handle,
        active: true
      ).order(:id).first
    end

    def reservation_denied?(entitlement)
      entitlement&.metadata&.fetch("reservation_denied", false) == true
    end

    def explicit_candidate_selector?(normalized_selector)
      normalized_selector.start_with?("candidate:")
    end

    def resolution_reason(normalized_selector, fallback_count, last_fallback_reason)
      return "explicit_candidate" if explicit_candidate_selector?(normalized_selector)
      return last_fallback_reason if fallback_count.positive?

      "role_primary"
    end

    def catalog
      @catalog ||= ProviderCatalog::Load.call
    end

    def raise_unavailable!(message)
      @turn.errors.add(:resolved_model_selection_snapshot, message)
      raise ActiveRecord::RecordInvalid, @turn
    end
  end
end
