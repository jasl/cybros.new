module InstallationScopedLookup
  extend ActiveSupport::Concern

  private

  def current_installation_id
    raise NotImplementedError, "#{self.class.name} must implement #current_installation_id"
  end

  def find_workspace!(workspace_id)
    workspace_lookup_scope.find_by!(public_id: workspace_id)
  end

  def find_agent!(agent_id)
    agent_lookup_scope.find_by!(public_id: agent_id)
  end

  def find_execution_runtime!(execution_runtime_id)
    execution_runtime_lookup_scope.find_by!(public_id: execution_runtime_id)
  end

  def find_conversation!(conversation_id, workspace: nil)
    conversation_lookup_scope(workspace: workspace).find_by!(public_id: conversation_id)
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

  def workspace_lookup_scope
    Workspace.where(installation_id: current_installation_id)
  end

  def agent_lookup_scope
    Agent.where(installation_id: current_installation_id)
  end

  def execution_runtime_lookup_scope
    ExecutionRuntime.where(installation_id: current_installation_id)
  end

  def conversation_lookup_scope(workspace: nil)
    scope = Conversation.where(
      installation_id: current_installation_id,
      deletion_state: "retained"
    )
    scope = scope.where(workspace_id: workspace.id) if workspace.present?
    scope
  end
end
