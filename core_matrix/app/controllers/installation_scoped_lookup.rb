module InstallationScopedLookup
  extend ActiveSupport::Concern

  private

  def current_installation_id
    raise NotImplementedError, "#{self.class.name} must implement #current_installation_id"
  end

  def find_workspace!(workspace_id)
    Workspace.find_by!(
      public_id: workspace_id,
      installation_id: current_installation_id
    )
  end

  def find_conversation!(conversation_id, workspace: nil)
    scope = {
      public_id: conversation_id,
      installation_id: current_installation_id,
      deletion_state: "retained",
    }
    scope[:workspace_id] = workspace.id if workspace.present?

    Conversation.find_by!(scope)
  end

  def find_turn!(turn_id)
    Turn.find_by!(
      public_id: turn_id,
      installation_id: current_installation_id
    )
  end

  def find_workflow_run!(workflow_run_id)
    WorkflowRun.find_by!(
      public_id: workflow_run_id,
      installation_id: current_installation_id
    )
  end

  def find_workflow_node!(workflow_node_id)
    WorkflowNode.find_by!(
      public_id: workflow_node_id,
      installation_id: current_installation_id
    )
  end

  def find_agent_task_run!(agent_task_run_id)
    AgentTaskRun.find_by!(
      public_id: agent_task_run_id,
      installation_id: current_installation_id
    )
  end

  def find_tool_invocation!(tool_invocation_id)
    ToolInvocation.find_by!(
      public_id: tool_invocation_id,
      installation_id: current_installation_id
    )
  end

  def find_command_run!(command_run_id)
    CommandRun.find_by!(
      public_id: command_run_id,
      installation_id: current_installation_id
    )
  end

  def find_message_attachment!(attachment_id)
    MessageAttachment.find_by!(
      public_id: attachment_id,
      installation_id: current_installation_id
    )
  end
end
