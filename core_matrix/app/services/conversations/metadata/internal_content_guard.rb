module Conversations
  module Metadata
    module InternalContentGuard
      INTERNAL_TOKEN_PATTERN = /\b(?:workflow_run(?:_id)?|workflow_node(?:_id)?|agent_task_run(?:_id)?|tool_invocation(?:_id)?|subagent_session(?:_id)?|provider_request_id|command_run(?:_id)?|process_run(?:_id)?|public_id)\b/i
      ID_LABEL_WITH_BIGINT_PATTERN = /\b(?:id|public_id|workflow_run_id|workflow_node_id|agent_task_run_id|tool_invocation_id|subagent_session_id|provider_request_id|command_run_id|process_run_id)\b\s*(?:[:=]\s*|\s+)\d{10,}\b/i

      def self.internal_metadata_content?(value)
        return false unless value.is_a?(String)
        return true if value.match?(ID_LABEL_WITH_BIGINT_PATTERN)

        value.match?(INTERNAL_TOKEN_PATTERN)
      end
    end
  end
end
