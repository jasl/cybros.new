class TurnExecutionSnapshot
  def initialize(turn: nil, payload: nil)
    raise ArgumentError, "turn or payload is required" if turn.nil? && payload.nil?
    @turn = turn
    @payload = payload&.deep_stringify_keys
  end

  def to_h
    return payload.deep_dup if payload.present?

    {
      "identity" => identity,
      "task" => task,
      "conversation_projection" => conversation_projection,
      "capability_projection" => capability_projection,
      "provider_context" => provider_context,
      "runtime_context" => runtime_context,
      "workspace_agent_context" => workspace_agent_context,
      "turn_origin" => turn_origin,
      "attachment_manifest" => attachment_manifest,
      "model_input_attachments" => model_input_attachments,
      "attachment_diagnostics" => attachment_diagnostics,
    }
  end

  def identity
    return read_hash("identity") if payload.present?

    @identity ||= execution_contract&.identity || {}
  end

  def selected_input_message_id
    identity["selected_input_message_id"]
  end

  def turn_origin
    return read_hash("turn_origin") if payload.present?

    @turn_origin ||= execution_contract&.turn_origin_payload || {}
  end

  def task
    return read_hash("task") if payload.present?

    @task ||= execution_contract&.task || {}
  end

  def conversation_projection
    return read_hash("conversation_projection") if payload.present?

    @conversation_projection ||= {
      "messages" => materialized_messages,
      "context_imports" => materialized_context_imports,
      "prior_tool_results" => [],
      "projection_fingerprint" => execution_context_snapshot&.projection_fingerprint,
    }.compact
  end

  def capability_projection
    return read_hash("capability_projection") if payload.present?

    @capability_projection ||= begin
      snapshot = execution_capability_snapshot
      if snapshot.blank?
        {}
      else
        {
          "tool_surface" => snapshot.tool_surface,
          "profile_key" => snapshot.profile_key,
          "is_subagent" => snapshot.subagent,
          "subagent_connection_id" => snapshot.subagent_connection&.public_id,
          "parent_subagent_connection_id" => snapshot.parent_subagent_connection&.public_id,
          "subagent_depth" => snapshot.subagent_depth,
          "owner_conversation_id" => snapshot.owner_conversation&.public_id,
          "subagent_policy" => snapshot.subagent_policy_snapshot.deep_dup,
        }.compact
      end
    end
  end

  def provider_context
    return read_hash("provider_context") if payload.present?

    @provider_context ||= execution_contract&.provider_context_payload || {}
  end

  def runtime_context
    return read_hash("runtime_context") if payload.present?

    @runtime_context ||= begin
      if turn.blank?
        {}
      else
        {
          "control_plane" => "agent",
          "logical_work_id" => nil,
          "attempt_no" => nil,
          "agent_definition_version_id" => turn.agent_definition_version.public_id,
          "agent_id" => turn.agent_definition_version.agent.public_id,
          "user_id" => turn.conversation.workspace.user.public_id,
          "execution_runtime_id" => turn.execution_runtime&.public_id,
          "execution_runtime_version_id" => turn.execution_runtime_version&.public_id,
        }.compact
      end
    end
  end

  def workspace_agent_context
    return read_hash("workspace_agent_context") if payload.present?

    @workspace_agent_context ||= begin
      workspace_agent = turn&.conversation&.workspace_agent
      if workspace_agent.blank?
        {}
      else
        {
          "workspace_agent_id" => workspace_agent.public_id,
          "global_instructions" => execution_contract&.workspace_agent_global_instructions,
        }.compact
      end
    end
  end

  def context_imports
    conversation_projection.fetch("context_imports", [])
  end

  def model_context
    provider_context.fetch("model_context", {})
  end

  def provider_execution
    provider_context.fetch("provider_execution", {})
  end

  def budget_hints
    provider_context.fetch("budget_hints", {})
  end

  def attachment_manifest
    return read_array("attachment_manifest") if payload.present?

    @attachment_manifest ||= execution_contract&.attachment_manifest_payload || []
  end

  def model_input_attachments
    return read_array("model_input_attachments") if payload.present?

    @model_input_attachments ||= execution_contract&.model_input_attachments_payload || []
  end

  def attachment_diagnostics
    return read_array("attachment_diagnostics") if payload.present?

    @attachment_diagnostics ||= execution_contract&.attachment_diagnostics_payload || []
  end

  private

  attr_reader :turn
  attr_reader :payload

  def execution_contract
    @execution_contract ||= turn.execution_contract
  end

  def execution_context_snapshot
    execution_contract&.execution_context_snapshot
  end

  def execution_capability_snapshot
    execution_contract&.execution_capability_snapshot
  end

  def materialized_messages
    return @materialized_messages if defined?(@materialized_messages)

    refs = execution_context_snapshot&.message_refs_list || []
    return @materialized_messages = [] if refs.empty?

    messages_by_public_id = Message.where(
      installation_id: turn.installation_id,
      public_id: refs.map { |entry| entry.fetch("message_id") }
    ).includes(:conversation, :turn).index_by(&:public_id)

    @materialized_messages = refs.filter_map do |ref|
      message = messages_by_public_id[ref.fetch("message_id")]
      next if message.blank?

      {
        "message_id" => message.public_id,
        "conversation_id" => message.conversation.public_id,
        "turn_id" => message.turn.public_id,
        "role" => provider_role_for(message),
        "slot" => message.slot,
        "content" => message.content,
      }
    end
  end

  def materialized_context_imports
    return @materialized_context_imports if defined?(@materialized_context_imports)

    refs = execution_context_snapshot&.import_refs_list || []
    return @materialized_context_imports = [] if refs.empty?

    source_messages = Message.where(
      installation_id: turn.installation_id,
      public_id: refs.map { |entry| entry["source_message_id"] }.compact
    ).includes(:conversation).index_by(&:public_id)
    source_conversations = Conversation.where(
      installation_id: turn.installation_id,
      public_id: refs.map { |entry| entry["source_conversation_id"] }.compact
    ).index_by(&:public_id)
    summary_segments = ConversationSummarySegment.where(
      installation_id: turn.installation_id,
      id: refs.map { |entry| entry["summary_segment_id"] }.compact
    ).includes(:conversation).index_by(&:id)

    @materialized_context_imports = refs.filter_map do |ref|
      source_message = source_messages[ref["source_message_id"]]
      summary_segment = summary_segments[ref["summary_segment_id"]]
      source_conversation = source_conversations[ref["source_conversation_id"]] || summary_segment&.conversation || source_message&.conversation

      {
        "kind" => ref.fetch("kind"),
        "source_conversation_id" => source_conversation&.public_id,
        "source_message_id" => source_message&.public_id,
        "content" => summary_segment&.content || source_message&.content,
      }.compact
    end
  end

  def provider_role_for(message)
    case message.role
    when "agent"
      "assistant"
    else
      message.role
    end
  end

  def read_hash(key)
    value = payload[key]
    value.is_a?(Hash) ? value.deep_dup : {}
  end

  def read_array(key)
    value = payload[key]
    value.is_a?(Array) ? value.deep_dup : []
  end
end
