module ProviderCatalog
  class EffectiveCatalog
    AvailabilityResult = Struct.new(:usable, :reason_key, :provider_handle, :model_ref, :entitlement, keyword_init: true) do
      def usable?
        usable
      end
    end

    ResolveResult = Struct.new(
      :usable,
      :normalized_selector,
      :resolved_role_name,
      :provider_handle,
      :model_ref,
      :entitlement,
      :fallback_count,
      :resolution_reason,
      :reason_key,
      keyword_init: true
    ) do
      def usable?
        usable
      end
    end

    def initialize(installation: nil, env: Rails.env, catalog: ProviderCatalog::Registry.current)
      @installation = installation
      @env = env
      @catalog = catalog || ProviderCatalog::Registry.current
    end

    def provider(handle)
      @catalog.provider(handle)
    end

    def model(provider_handle, model_ref)
      @catalog.model(provider_handle, model_ref)
    end

    def role_candidates(role_name)
      @catalog.role_candidates(role_name)
    end

    def provider_governor(provider_handle)
      provider_key = provider_handle.to_s
      provider_definition = provider(provider_key)
      policy = ProviderPolicy.find_by(installation: @installation, provider_handle: provider_key)
      defaults = provider_definition.fetch(:request_governor, {})

      {
        "max_concurrent_requests" => policy&.max_concurrent_requests || defaults[:max_concurrent_requests],
        "throttle_limit" => policy&.throttle_limit || defaults[:throttle_limit],
        "throttle_period_seconds" => policy&.throttle_period_seconds || defaults[:throttle_period_seconds],
      }.compact
    end

    def selector_kind(selector)
      candidate_selector?(selector) ? "candidate" : "role"
    end

    def candidate_selector?(selector)
      normalize_selector(selector).start_with?("candidate:")
    end

    def role_selector?(selector)
      !candidate_selector?(selector)
    end

    def selector_option(selector:)
      normalized_selector = normalize_selector(selector)
      return build_candidate_option(normalized_selector) if candidate_selector?(normalized_selector)

      build_role_option(normalized_selector)
    end

    def selector_options(query: nil, provider_handle: nil, role_name: nil, include_roles: true, include_candidates: true, only_usable: false)
      options = []
      options.concat(role_options(query:, only_usable:)) if include_roles
      options.concat(candidate_options(query:, provider_handle:, role_name:, only_usable:)) if include_candidates
      options
    end

    def role_options(query: nil, only_usable: false)
      normalized_query = normalize_query(query)

      @catalog.model_roles.keys.sort.filter_map do |role_name|
        option = build_role_option("role:#{role_name}")
        next if only_usable && !option.fetch("usable")
        next unless matches_query?(
          normalized_query,
          option.fetch("selector"),
          option.fetch("label"),
          option["resolved_candidate_ref"],
          option["resolved_provider_handle"],
          option["resolved_model_ref"]
        )

        option
      end
    end

    def candidate_options(query: nil, provider_handle: nil, role_name: nil, only_usable: false)
      normalized_query = normalize_query(query)

      candidate_refs_for(provider_handle:, role_name:).filter_map do |candidate_ref|
        option = build_candidate_option("candidate:#{candidate_ref}")
        next if only_usable && !option.fetch("usable")

        next unless matches_query?(
          normalized_query,
          option.fetch("selector"),
          option.fetch("candidate_ref"),
          option.fetch("label"),
          option.fetch("provider_handle"),
          option.fetch("provider_display_name"),
          option.fetch("model_ref"),
          option.fetch("model_display_name")
        )

        option
      end
    end

    def available_candidates(role_name)
      role_candidates(role_name).select do |candidate_ref|
        provider_handle, model_ref = candidate_ref.split("/", 2)
        availability(provider_handle: provider_handle, model_ref: model_ref).usable?
      end
    end

    def availability(provider_handle:, model_ref:)
      provider_key = provider_handle.to_s
      model_key = model_ref.to_s
      provider_definition = @catalog.providers[provider_key]
      return unavailable_availability(provider_handle: provider_key, model_ref: model_key, reason_key: "unknown_provider") if provider_definition.blank?

      model_definition = provider_definition.fetch(:models)[model_key]
      return unavailable_availability(provider_handle: provider_key, model_ref: model_key, reason_key: "unknown_model") if model_definition.blank?
      return unavailable_availability(provider_handle: provider_key, model_ref: model_key, reason_key: "model_disabled") unless model_definition.fetch(:enabled)
      return unavailable_availability(provider_handle: provider_key, model_ref: model_key, reason_key: "provider_disabled") unless provider_definition.fetch(:enabled)
      return unavailable_availability(provider_handle: provider_key, model_ref: model_key, reason_key: "environment_not_allowed") unless provider_definition.fetch(:environments).include?(@env.to_s)
      return unavailable_availability(provider_handle: provider_key, model_ref: model_key, reason_key: "policy_disabled") if policy_disabled?(provider_key)

      entitlement = active_entitlement(provider_key)
      return unavailable_availability(provider_handle: provider_key, model_ref: model_key, reason_key: "missing_entitlement") if entitlement.blank?

      if provider_definition.fetch(:requires_credential) && matching_credential(provider_key, provider_definition.fetch(:credential_kind)).blank?
        return unavailable_availability(provider_handle: provider_key, model_ref: model_key, reason_key: "missing_credential")
      end

      AvailabilityResult.new(
        usable: true,
        reason_key: nil,
        provider_handle: provider_key,
        model_ref: model_key,
        entitlement: entitlement
      )
    rescue KeyError
      unavailable_availability(provider_handle: provider_key, model_ref: model_key, reason_key: "unknown_model")
    end

    def normalize_selector(selector)
      selector = selector&.to_s
      return "role:main" if selector.blank?
      return selector if selector.start_with?("role:", "candidate:")
      return "candidate:#{selector}" if selector.include?("/")

      "role:#{selector}"
    end

    def resolve_selector(selector:)
      normalized_selector = normalize_selector(selector)

      if candidate_selector?(normalized_selector)
        return resolve_explicit_candidate(normalized_selector)
      end

      resolve_role_selector(normalized_selector)
    end

    private

    def candidate_refs_for(provider_handle:, role_name:)
      refs = if role_name.present?
        role_candidates(role_name)
      elsif provider_handle.present?
        provider(provider_handle).fetch(:models).keys.sort.map { |model_ref| "#{provider_handle}/#{model_ref}" }
      else
        @catalog.providers.keys.sort.flat_map do |provider_key|
          provider(provider_key).fetch(:models).keys.sort.map { |model_ref| "#{provider_key}/#{model_ref}" }
        end
      end

      refs.uniq
    end

    def normalize_query(query)
      query.to_s.strip.downcase.presence
    end

    def matches_query?(normalized_query, *values)
      return true if normalized_query.blank?

      values.compact.any? { |value| value.to_s.downcase.include?(normalized_query) }
    end

    def policy_disabled?(provider_handle)
      ProviderPolicy.find_by(installation: @installation, provider_handle: provider_handle)&.enabled == false
    end

    def active_entitlement(provider_handle)
      ProviderEntitlement.where(
        installation: @installation,
        provider_handle: provider_handle,
        active: true
      ).order(:id).first
    end

    def matching_credential(provider_handle, credential_kind)
      ProviderCredential.find_by(
        installation: @installation,
        provider_handle: provider_handle,
        credential_kind: credential_kind
      )
    end

    def unavailable_availability(provider_handle:, model_ref:, reason_key:)
      AvailabilityResult.new(
        usable: false,
        reason_key: reason_key,
        provider_handle: provider_handle,
        model_ref: model_ref,
        entitlement: nil
      )
    end

    def resolve_explicit_candidate(normalized_selector)
      provider_handle, model_ref = normalized_selector.delete_prefix("candidate:").split("/", 2)
      availability = availability(provider_handle:, model_ref:)
      return unavailable_result(normalized_selector:, reason_key: availability.reason_key) unless availability.usable?
      return unavailable_result(normalized_selector:, reason_key: "reservation_denied") if reservation_denied?(availability.entitlement)

      ResolveResult.new(
        usable: true,
        normalized_selector: normalized_selector,
        resolved_role_name: nil,
        provider_handle: provider_handle,
        model_ref: model_ref,
        entitlement: availability.entitlement,
        fallback_count: 0,
        resolution_reason: "explicit_candidate",
        reason_key: nil
      )
    end

    def resolve_role_selector(normalized_selector)
      role_name = normalized_selector.delete_prefix("role:")
      candidates = role_candidates(role_name)
      fallback_count = 0
      last_fallback_reason = nil

      candidates.each do |candidate_ref|
        provider_handle, model_ref = candidate_ref.split("/", 2)
        availability = availability(provider_handle:, model_ref:)

        unless availability.usable?
          fallback_count += 1
          last_fallback_reason = "role_fallback_after_filter"
          next
        end

        if reservation_denied?(availability.entitlement)
          fallback_count += 1
          last_fallback_reason = "role_fallback_after_reservation"
          next
        end

        return ResolveResult.new(
          usable: true,
          normalized_selector: normalized_selector,
          resolved_role_name: role_name,
          provider_handle: provider_handle,
          model_ref: model_ref,
          entitlement: availability.entitlement,
          fallback_count: fallback_count,
          resolution_reason: fallback_count.positive? ? last_fallback_reason : "role_primary",
          reason_key: nil
        )
      end

      unavailable_result(
        normalized_selector: normalized_selector,
        resolved_role_name: role_name,
        fallback_count: fallback_count,
        resolution_reason: last_fallback_reason,
        reason_key: "no_candidate_available"
      )
    rescue KeyError
      unavailable_result(
        normalized_selector: normalized_selector,
        resolved_role_name: role_name,
        fallback_count: 0,
        resolution_reason: nil,
        reason_key: "unknown_model_role"
      )
    end

    def build_role_option(normalized_selector)
      role_name = normalized_selector.delete_prefix("role:")
      result = resolve_selector(selector: normalized_selector)

      {
        "kind" => "role",
        "selector" => normalized_selector,
        "label" => role_name,
        "role_name" => role_name,
        "candidate_refs" => role_candidates(role_name),
        "usable" => result.usable?,
        "reason_key" => result.reason_key,
        "resolved_candidate_ref" => result.usable? ? "#{result.provider_handle}/#{result.model_ref}" : nil,
        "resolved_provider_handle" => result.provider_handle,
        "resolved_model_ref" => result.model_ref,
        "fallback_count" => result.fallback_count,
        "resolution_reason" => result.resolution_reason,
      }.compact
    rescue KeyError
      {
        "kind" => "role",
        "selector" => normalized_selector,
        "label" => role_name,
        "role_name" => role_name,
        "candidate_refs" => [],
        "usable" => false,
        "reason_key" => "unknown_model_role",
        "fallback_count" => 0,
      }
    end

    def build_candidate_option(normalized_selector)
      provider_handle, model_ref = normalized_selector.delete_prefix("candidate:").split("/", 2)
      provider_definition = @catalog.providers[provider_handle]
      model_definition = provider_definition&.fetch(:models, {})&.[](model_ref)
      availability = availability(provider_handle:, model_ref:)

      provider_display_name = provider_definition&.fetch(:display_name, provider_handle) || provider_handle
      model_display_name = model_definition&.fetch(:display_name, model_ref) || model_ref
      candidate_ref = "#{provider_handle}/#{model_ref}"

      {
        "kind" => "candidate",
        "selector" => normalized_selector,
        "label" => "#{provider_display_name} / #{model_display_name}",
        "candidate_ref" => candidate_ref,
        "provider_handle" => provider_handle,
        "provider_display_name" => provider_display_name,
        "model_ref" => model_ref,
        "model_display_name" => model_display_name,
        "usable" => availability.usable?,
        "reason_key" => availability.reason_key,
        "entitlement_key" => availability.entitlement&.entitlement_key,
      }.compact
    end

    def reservation_denied?(entitlement)
      entitlement&.metadata&.fetch("reservation_denied", false) == true
    end

    def unavailable_result(normalized_selector:, reason_key:, resolved_role_name: nil, fallback_count: 0, resolution_reason: nil)
      ResolveResult.new(
        usable: false,
        normalized_selector: normalized_selector,
        resolved_role_name: resolved_role_name,
        provider_handle: nil,
        model_ref: nil,
        entitlement: nil,
        fallback_count: fallback_count,
        resolution_reason: resolution_reason,
        reason_key: reason_key
      )
    end
  end
end
