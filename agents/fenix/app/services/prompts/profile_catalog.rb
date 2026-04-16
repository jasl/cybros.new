module Prompts
  class ProfileCatalog
    def initialize(bundles:)
      @bundles = bundles.deep_stringify_keys
    end

    def keys_for(group, include_hidden: false)
      bundles_for(group, include_hidden:).keys.sort
    end

    def fetch(group:, key:)
      @bundles.fetch(group.to_s).fetch(key.to_s)
    end

    def resolve(profile_key:, is_subagent:)
      group = is_subagent ? "specialists" : "main"
      return fetch(group:, key: profile_key) if @bundles.fetch(group, {}).key?(profile_key.to_s)

      raise KeyError, "Unknown #{group.singularize} profile #{profile_key.inspect}"
    end

    def resolve_with_fallback(profile_key:, is_subagent:)
      resolve(profile_key:, is_subagent:)
    rescue KeyError
      fallback_bundle
    end

    def enabled_specialists(keys)
      Array(keys).filter_map do |key|
        @bundles.fetch("specialists", {})[key.to_s]
      end
    end

    def default_interactive_key
      fallback_key
    end

    def visible_profiles
      %w[main specialists].each_with_object({}) do |group, memo|
        bundles_for(group, include_hidden: false).each_value do |bundle|
          memo[bundle.key] = {
            "label" => bundle.label,
            "description" => bundle.description,
          }
        end
      end
    end

    private

    def bundles_for(group, include_hidden:)
      bundles = @bundles.fetch(group.to_s, {})
      return bundles if include_hidden

      bundles.reject { |_key, bundle| bundle.hidden? }
    end

    def fallback_bundle
      main_bundles = @bundles.fetch("main", {})
      return main_bundles.fetch("default") if main_bundles.key?("default")

      main_bundles.sort.first&.last || @bundles.fetch("specialists", {}).sort.first&.last ||
        raise(KeyError, "No prompt profiles available")
    end

    def fallback_key
      fallback_bundle.key
    end
  end
end
