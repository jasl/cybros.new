module Prompts
  class ProfileCatalog
    def initialize(bundles:)
      @bundles = bundles.deep_stringify_keys
    end

    def keys_for(group)
      @bundles.fetch(group.to_s, {}).keys.sort
    end

    def fetch(group:, key:)
      @bundles.fetch(group.to_s).fetch(key.to_s)
    end

    def resolve(profile_key:, is_subagent:)
      group = is_subagent ? "specialists" : "main"
      return fetch(group:, key: profile_key) if @bundles.fetch(group, {}).key?(profile_key.to_s)

      raise KeyError, "Unknown #{group.singularize} profile #{profile_key.inspect}"
    end

    def enabled_specialists(keys)
      Array(keys).filter_map do |key|
        @bundles.fetch("specialists", {})[key.to_s]
      end
    end
  end
end
