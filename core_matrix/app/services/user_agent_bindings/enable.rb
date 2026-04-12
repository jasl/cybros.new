module UserAgentBindings
  class Enable
    AccessDenied = Class.new(StandardError)

    Result = Struct.new(:binding, :default_workspace_ref, keyword_init: true)

    def self.call(...)
      new(...).call
    end

    def initialize(user:, agent:)
      @user = user
      @agent = agent
    end

    def call
      validate_installation!
      validate_visibility!

      ApplicationRecord.transaction do
        binding = find_or_create_binding!

        Result.new(
          binding: binding,
          default_workspace_ref: Workspaces::BuildDefaultReference.call(user_agent_binding: binding)
        )
      end
    end

    private

    def validate_installation!
      return if @user.installation_id == @agent.installation_id

      raise ArgumentError, "user and agent must belong to the same installation"
    end

    def validate_visibility!
      return if @agent.visibility_public?
      return if @agent.visibility_private? && @agent.owner_user_id == @user.id

      raise AccessDenied, "user cannot enable this private agent"
    end

    def find_or_create_binding!
      UserAgentBinding.find_or_create_by!(
        installation: @user.installation,
        user: @user,
        agent: @agent
      ) do |record|
        record.preferences = {}
      end
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
      UserAgentBinding.find_by(
        installation: @user.installation,
        user: @user,
        agent: @agent
      ) || raise
    end
  end
end
