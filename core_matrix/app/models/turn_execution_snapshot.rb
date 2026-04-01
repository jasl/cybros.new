class TurnExecutionSnapshot
  def initialize(payload)
    @payload = payload.deep_dup
  end

  def to_h
    @payload.deep_dup
  end

  def identity
    read_hash("identity")
  end

  def selected_input_message_id
    identity["selected_input_message_id"]
  end

  def turn_origin
    read_hash("turn_origin")
  end

  def task
    read_hash("task")
  end

  def conversation_projection
    read_hash("conversation_projection")
  end

  def capability_projection
    read_hash("capability_projection")
  end

  def provider_context
    read_hash("provider_context")
  end

  def runtime_context
    read_hash("runtime_context")
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
    read_array("attachment_manifest")
  end

  def runtime_attachment_manifest
    read_array("runtime_attachment_manifest")
  end

  def model_input_attachments
    read_array("model_input_attachments")
  end

  def attachment_diagnostics
    read_array("attachment_diagnostics")
  end

  private

  def read_hash(key)
    value = @payload[key]
    value.is_a?(Hash) ? value.deep_dup : {}
  end

  def read_array(key)
    value = @payload[key]
    value.is_a?(Array) ? value.deep_dup : []
  end
end
