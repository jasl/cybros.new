module Variables
  class Write
    def self.call(...)
      new(...).call
    end

    def initialize(scope:, workspace:, key:, typed_value_payload:, writer: nil, source_kind:, conversation: nil, source_conversation: nil, source_turn: nil, source_workflow_run: nil, projection_policy: "silent")
      @scope = scope.to_s
      @workspace = workspace
      @key = key
      @typed_value_payload = typed_value_payload
      @writer = writer
      @source_kind = source_kind
      @conversation = conversation
      @source_conversation = source_conversation || conversation || source_turn&.conversation || source_workflow_run&.conversation
      @source_turn = source_turn
      @source_workflow_run = source_workflow_run
      @projection_policy = projection_policy
    end

    def call
      ApplicationRecord.transaction do
        current_variable = current_scope_relation.lock.first
        prepare_supersession!(current_variable) if current_variable.present?
        variable = CanonicalVariable.create!(
          installation: @workspace.installation,
          workspace: @workspace,
          conversation: scoped_conversation,
          scope: @scope,
          key: @key,
          typed_value_payload: @typed_value_payload,
          writer: @writer,
          source_kind: @source_kind,
          source_conversation: @source_conversation,
          source_turn: @source_turn,
          source_workflow_run: @source_workflow_run,
          projection_policy: @projection_policy,
          current: true
        )

        finalize_supersession!(current_variable, variable) if current_variable.present?
        variable
      end
    end

    private

    def scoped_conversation
      @scope == "conversation" ? @conversation : nil
    end

    def current_scope_relation
      relation = CanonicalVariable.where(
        workspace: @workspace,
        scope: @scope,
        key: @key,
        current: true
      )
      return relation.where(conversation: @conversation) if @scope == "conversation"

      relation.where(conversation: nil)
    end

    def prepare_supersession!(current_variable)
      current_variable.update_columns(
        current: false,
        superseded_at: Time.current,
        updated_at: Time.current
      )
    end

    def finalize_supersession!(current_variable, replacement)
      current_variable.update_columns(
        superseded_by_id: replacement.id,
        updated_at: Time.current
      )
    end
  end
end
