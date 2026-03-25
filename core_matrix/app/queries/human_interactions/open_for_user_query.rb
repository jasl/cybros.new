module HumanInteractions
  class OpenForUserQuery
    def self.call(...)
      new(...).call
    end

    def initialize(user:)
      @user = user
    end

    def call
      HumanInteractionRequest
        .joins(conversation: :workspace)
        .includes(:conversation, :turn, :workflow_run, :workflow_node)
        .where(installation: @user.installation, lifecycle_state: "open")
        .where(conversations: { deletion_state: "retained", lifecycle_state: "active" })
        .where(workspaces: { installation_id: @user.installation_id, user_id: @user.id, privacy: "private" })
        .order(:created_at, :id)
        .to_a
    end
  end
end
