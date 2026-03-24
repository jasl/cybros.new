module UserAgentBindings
  class Enable
    AccessDenied = Class.new(StandardError)

    Result = Struct.new(:binding, :workspace, keyword_init: true)

    def self.call(...)
      new(...).call
    end

    def initialize(user:, agent_installation:)
      @user = user
      @agent_installation = agent_installation
    end

    def call
      validate_installation!
      validate_visibility!

      ApplicationRecord.transaction do
        binding = UserAgentBinding.find_or_create_by!(
          installation: @user.installation,
          user: @user,
          agent_installation: @agent_installation
        ) do |record|
          record.preferences = {}
        end
        workspace = Workspaces::CreateDefault.call(user_agent_binding: binding)

        Result.new(binding: binding, workspace: workspace)
      end
    end

    private

    def validate_installation!
      return if @user.installation_id == @agent_installation.installation_id

      raise ArgumentError, "user and agent installation must belong to the same installation"
    end

    def validate_visibility!
      return if @agent_installation.global?
      return if @agent_installation.owner_user_id == @user.id

      raise AccessDenied, "user cannot enable this personal agent installation"
    end
  end
end
