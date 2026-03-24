module Variables
  class PromoteToWorkspace
    def self.call(...)
      new(...).call
    end

    def initialize(conversation_variable:, writer: nil)
      @conversation_variable = conversation_variable
      @writer = writer
    end

    def call
      raise_invalid!(@conversation_variable, :scope, "must be conversation scope to promote to workspace") unless @conversation_variable.conversation_scope?
      raise_invalid!(@conversation_variable, :current, "must be current to promote to workspace") unless @conversation_variable.current?

      Variables::Write.call(
        scope: "workspace",
        workspace: @conversation_variable.workspace,
        key: @conversation_variable.key,
        typed_value_payload: @conversation_variable.typed_value_payload,
        writer: @writer || @conversation_variable.writer,
        source_kind: "promotion",
        source_conversation: @conversation_variable.conversation,
        source_turn: @conversation_variable.source_turn,
        source_workflow_run: @conversation_variable.source_workflow_run,
        projection_policy: @conversation_variable.projection_policy
      )
    end

    private

    def raise_invalid!(record, attribute, message)
      record.errors.add(attribute, message)
      raise ActiveRecord::RecordInvalid, record
    end
  end
end
