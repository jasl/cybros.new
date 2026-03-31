module RuntimeCapabilities
  class ResolveToolExecutionPolicy
    def self.call(...)
      new(...).call
    end

    def initialize(tool_entry:, overlays: [])
      @tool_entry = tool_entry.deep_stringify_keys
      @overlays = Array(overlays).filter_map do |entry|
        entry.is_a?(Hash) ? entry.deep_stringify_keys : nil
      end
    end

    def call
      policy = base_policy.merge(source_default_policy)

      matching_overlays.each do |overlay|
        policy.merge!(normalize_policy(overlay["execution_policy"]))
      end

      policy
    end

    private

    def base_policy
      normalize_policy(@tool_entry["execution_policy"])
    end

    def source_default_policy
      return { "parallel_safe" => false } if @tool_entry["implementation_source"] == "mcp"

      {}
    end

    def matching_overlays
      @overlays.select do |overlay|
        match = overlay["match"]
        next false unless match.is_a?(Hash) && match.present?

        match.all? do |key, expected|
          actual = matched_value_for(key)
          actual.present? && actual == expected
        end
      end
    end

    def matched_value_for(key)
      case key
      when "tool_source"
        @tool_entry["implementation_source"]
      when "server_slug"
        @tool_entry["mcp_server_slug"] || @tool_entry["server_slug"]
      else
        @tool_entry[key]
      end
    end

    def normalize_policy(policy)
      policy_hash =
        case policy
        when Hash
          policy.deep_stringify_keys
        else
          {}
        end

      {
        "parallel_safe" => policy_hash.fetch("parallel_safe", false),
      }
    end
  end
end
