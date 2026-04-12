module AppAPI
  # Product-facing API endpoints currently reuse agent-definition-version authentication
  # until the user-session API layer exists. Keeping a distinct namespace still
  # lets us separate product read/export surfaces from runtime resource APIs.
  class BaseController < AgentAPI::BaseController
    private

    def find_workspace!(workspace_id)
      workspace = super
      authorize_workspace_usability!(workspace)
    end

    def find_conversation!(conversation_id, workspace: nil)
      conversation = super
      authorize_conversation_usability!(conversation)
    end

    def authorize_workspace_usability!(workspace)
      raise ActiveRecord::RecordNotFound, "Couldn't find Workspace" unless resource_visibility_user_can_access_workspace?(workspace)

      workspace
    end

    def authorize_conversation_usability!(conversation)
      raise ActiveRecord::RecordNotFound, "Couldn't find Conversation" unless resource_visibility_user_can_access_conversation?(conversation)

      conversation
    end

    def resource_visibility_user_can_access_workspace?(workspace)
      ResourceVisibility::Usability.workspace_accessible_by_user?(user: workspace.user, workspace: workspace)
    end

    def resource_visibility_user_can_access_conversation?(conversation)
      ResourceVisibility::Usability.conversation_accessible_by_user?(user: conversation.workspace.user, conversation: conversation)
    end
  end
end
