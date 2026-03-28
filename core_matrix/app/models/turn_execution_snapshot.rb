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

  def turn_origin
    read_hash("turn_origin")
  end

  def model_context
    read_hash("model_context")
  end

  def provider_execution
    read_hash("provider_execution")
  end

  def budget_hints
    read_hash("budget_hints")
  end

  def agent_context
    read_hash("agent_context")
  end

  def context_messages
    read_array("context_messages")
  end

  def context_imports
    read_array("context_imports")
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
