module MachineAPISupport
  private

  def request_payload
    params.to_unsafe_h.except("controller", "action").deep_stringify_keys
  end

  def find_tool_binding_for_agent_task_run!(agent_task_run, tool_name)
    agent_task_run.tool_bindings
      .joins(:tool_definition)
      .find_by!(tool_definitions: { tool_name: tool_name })
  end

  def serialize_message(message)
    {
      "id" => message.public_id,
      "conversation_id" => message.conversation.public_id,
      "turn_id" => message.turn.public_id,
      "role" => message.role,
      "slot" => message.slot,
      "variant_index" => message.variant_index,
      "content" => message.content,
    }
  end

  def serialize_variable(variable, conversation: nil, scope: nil)
    return if variable.blank?

    if variable.is_a?(CanonicalVariable)
      return {
        "workspace_id" => variable.workspace.public_id,
        "scope" => variable.scope,
        "key" => variable.key,
        "typed_value_payload" => variable.typed_value_payload,
        "source_kind" => variable.source_kind,
        "projection_policy" => variable.projection_policy,
        "current" => variable.current,
      }
    end

    raise ArgumentError, "conversation is required for conversation store serialization" if conversation.blank?

    {
      "workspace_id" => conversation.workspace.public_id,
      "conversation_id" => conversation.public_id,
      "scope" => scope || "conversation",
      "key" => variable.key,
      "typed_value_payload" => variable.respond_to?(:typed_value_payload) ? variable.typed_value_payload : nil,
      "value_type" => variable.respond_to?(:value_type) ? variable.value_type : nil,
      "value_bytesize" => variable.respond_to?(:value_bytesize) ? variable.value_bytesize : nil,
      "current" => true,
    }.compact
  end

  def serialize_variable_metadata(metadata, conversation:)
    {
      "workspace_id" => conversation.workspace.public_id,
      "conversation_id" => conversation.public_id,
      "scope" => "conversation",
      "key" => metadata.key,
      "value_type" => metadata.value_type,
      "value_bytesize" => metadata.value_bytesize,
    }.compact
  end

  def serialize_human_interaction_request(request)
    {
      "request_id" => request.public_id,
      "request_type" => request.type,
      "workflow_run_id" => request.workflow_run.public_id,
      "workflow_node_id" => request.workflow_node.public_id,
      "conversation_id" => request.conversation.public_id,
      "turn_id" => request.turn.public_id,
      "lifecycle_state" => request.lifecycle_state,
      "blocking" => request.blocking,
      "request_payload" => request.request_payload,
      "result_payload" => request.result_payload,
    }
  end

  def serialize_tool_invocation(tool_invocation)
    {
      "tool_invocation_id" => tool_invocation.public_id,
      "agent_task_run_id" => tool_invocation.agent_task_run.public_id,
      "tool_binding_id" => tool_invocation.tool_binding.public_id,
      "tool_definition_id" => tool_invocation.tool_definition.public_id,
      "tool_implementation_id" => tool_invocation.tool_implementation.public_id,
      "tool_name" => tool_invocation.tool_definition.tool_name,
      "status" => tool_invocation.status,
      "request_payload" => tool_invocation.request_payload,
      "stream_output" => tool_invocation.stream_output == true,
    }
  end

  def serialize_command_run(command_run)
    {
      "command_run_id" => command_run.public_id,
      "tool_invocation_id" => command_run.tool_invocation.public_id,
      "agent_task_run_id" => command_run.agent_task_run.public_id,
      "lifecycle_state" => command_run.lifecycle_state,
      "command_line" => command_run.command_line,
      "timeout_seconds" => command_run.timeout_seconds,
      "pty" => command_run.pty,
    }
  end

  def serialize_process_run(process_run)
    {
      "process_run_id" => process_run.public_id,
      "workflow_node_id" => process_run.workflow_node.public_id,
      "conversation_id" => process_run.conversation.public_id,
      "turn_id" => process_run.turn.public_id,
      "kind" => process_run.kind,
      "lifecycle_state" => process_run.lifecycle_state,
      "command_line" => process_run.command_line,
      "timeout_seconds" => process_run.timeout_seconds,
    }
  end
end
