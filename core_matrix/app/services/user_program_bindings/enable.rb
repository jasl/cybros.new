module UserProgramBindings
  class Enable
    AccessDenied = Class.new(StandardError)

    Result = Struct.new(:binding, :workspace, keyword_init: true)

    def self.call(...)
      new(...).call
    end

    def initialize(user:, agent_program:)
      @user = user
      @agent_program = agent_program
    end

    def call
      validate_installation!
      validate_visibility!

      ApplicationRecord.transaction do
        binding = UserProgramBinding.find_or_create_by!(
          installation: @user.installation,
          user: @user,
          agent_program: @agent_program
        ) do |record|
          record.preferences = {}
        end
        workspace = Workspaces::CreateDefault.call(user_program_binding: binding)

        Result.new(binding: binding, workspace: workspace)
      end
    end

    private

    def validate_installation!
      return if @user.installation_id == @agent_program.installation_id

      raise ArgumentError, "user and agent program must belong to the same installation"
    end

    def validate_visibility!
      return if @agent_program.global?
      return if @agent_program.owner_user_id == @user.id

      raise AccessDenied, "user cannot enable this personal agent program"
    end
  end
end
