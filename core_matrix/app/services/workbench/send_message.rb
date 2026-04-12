module Workbench
  class SendMessage
    Result = Struct.new(:conversation, :turn, :workflow_run, :message, keyword_init: true)

    def self.call(...)
      new(...).call
    end

    def initialize(conversation:, content:, selector: nil, execution_runtime: nil)
      @conversation = conversation
      @content = content
      @selector = selector
      @execution_runtime = execution_runtime
    end

    def call
      turn = Turns::StartUserTurn.call(
        conversation: @conversation,
        content: @content,
        execution_runtime: @execution_runtime,
        resolved_config_snapshot: {},
        resolved_model_selection_snapshot: {}
      )
      workflow_run = Workflows::CreateForTurn.call(
        turn: turn,
        root_node_key: "turn_step",
        root_node_type: "turn_step",
        decision_source: "system",
        metadata: {},
        selector_source: @selector.present? ? "app_api" : "conversation",
        selector: @selector
      )
      Workflows::ExecuteRun.call(workflow_run: workflow_run)

      Result.new(
        conversation: @conversation,
        turn: turn,
        workflow_run: workflow_run,
        message: turn.selected_input_message
      )
    end
  end
end
