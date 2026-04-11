module Skills
  class ScopeRoots
    attr_reader :home_root, :agent_id, :user_id

    def initialize(agent_id:, user_id:, home_root:)
      @agent_id = agent_id.to_s
      @user_id = user_id.to_s
      @home_root = Pathname(home_root).expand_path

      validate_scope_component!("agent_id", @agent_id)
      validate_scope_component!("user_id", @user_id)
    end

    def live_root
      scope_root.join("live")
    end

    def staging_root
      scope_root.join("staging")
    end

    def backup_root
      scope_root.join("backups")
    end

    private

    def validate_scope_component!(name, value)
      raise ArgumentError, "#{name} is required" if value.blank?
      raise ArgumentError, "#{name} must not contain path separators" if value.include?(File::SEPARATOR)
      raise ArgumentError, "#{name} must not contain path separators" if File::ALT_SEPARATOR && value.include?(File::ALT_SEPARATOR)
      raise ArgumentError, "#{name} must not be '.' or '..'" if value == "." || value == ".."
    end

    def scope_root
      @scope_root ||= home_root.join("skills-scopes", agent_id, user_id)
    end
  end
end
