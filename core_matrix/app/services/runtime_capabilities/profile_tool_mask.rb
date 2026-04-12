module RuntimeCapabilities
  class ProfileToolMask
    def self.call(...)
      new(...).call
    end

    def self.tool_names(...)
      call(...).map { |entry| entry.fetch("tool_name") }.uniq
    end

    def initialize(tool_catalog:, profile:)
      @tool_catalog = Array(tool_catalog).map { |entry| entry.deep_stringify_keys }
      @profile = profile.is_a?(Hash) ? profile.deep_stringify_keys : {}
    end

    def call
      return tool_catalog.map(&:deep_dup) unless tool_restrictions_configured?

      tool_catalog.select do |entry|
        explicitly_allowed_tool?(entry) || execution_runtime_tool_allowed?(entry)
      end.map(&:deep_dup)
    end

    private

    attr_reader :tool_catalog
    attr_reader :profile

    def tool_restrictions_configured?
      profile.key?("allowed_tool_names") || allow_execution_runtime_tools?
    end

    def explicitly_allowed_tool?(entry)
      allowed_tool_names.include?(entry.fetch("tool_name"))
    end

    def execution_runtime_tool_allowed?(entry)
      allow_execution_runtime_tools? && entry.fetch("implementation_source", nil) == "execution_runtime"
    end

    def allowed_tool_names
      @allowed_tool_names ||= Array(profile["allowed_tool_names"]).map(&:to_s)
    end

    def allow_execution_runtime_tools?
      profile["allow_execution_runtime_tools"] == true
    end
  end
end
