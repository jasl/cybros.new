module ConversationSupervision
  class BuildRuntimeEvidence
    ACTIVE_COMMAND_STATES = %w[starting running].freeze
    ACTIVE_PROCESS_STATES = %w[starting running].freeze
    TERMINAL_COMMAND_STATES = %w[completed failed interrupted canceled].freeze
    TERMINAL_PROCESS_STATES = %w[stopped failed lost].freeze

    def self.call(...)
      new(...).call
    end

    def initialize(conversation:, workflow_run: nil)
      @conversation = conversation
      @workflow_run = workflow_run
    end

    def call
      {
        "active_command" => serialize_command(active_command_run),
        "recent_command" => serialize_command(recent_command_run),
        "active_process" => serialize_process(active_process_run),
        "recent_process" => serialize_process(recent_process_run),
        "workflow_wait_state" => workflow_run&.wait_state,
      }.compact
    end

    private

    def workflow_run
      return @workflow_run if instance_variable_defined?(:@workflow_run)

      @workflow_run = @conversation.workflow_runs.order(created_at: :desc).first
    end

    def workflow_node_ids
      @workflow_node_ids ||= workflow_run.present? ? workflow_run.workflow_nodes.select(:id) : WorkflowNode.none
    end

    def command_runs
      @command_runs ||= CommandRun.where(workflow_node_id: workflow_node_ids)
    end

    def process_runs
      @process_runs ||= workflow_run.present? ? workflow_run.process_runs : ProcessRun.none
    end

    def active_command_run
      return @active_command_run if instance_variable_defined?(:@active_command_run)

      @active_command_run = command_runs
        .where(lifecycle_state: ACTIVE_COMMAND_STATES)
        .order(started_at: :desc, created_at: :desc)
        .first
    end

    def recent_command_run
      return @recent_command_run if instance_variable_defined?(:@recent_command_run)

      @recent_command_run = command_runs
        .where.not(id: active_command_run&.id)
        .where(lifecycle_state: TERMINAL_COMMAND_STATES)
        .order(ended_at: :desc, started_at: :desc, created_at: :desc)
        .first
    end

    def active_process_run
      return @active_process_run if instance_variable_defined?(:@active_process_run)

      @active_process_run = process_runs
        .where(lifecycle_state: ACTIVE_PROCESS_STATES)
        .order(started_at: :desc, created_at: :desc)
        .first
    end

    def recent_process_run
      return @recent_process_run if instance_variable_defined?(:@recent_process_run)

      @recent_process_run = process_runs
        .where.not(id: active_process_run&.id)
        .where(lifecycle_state: TERMINAL_PROCESS_STATES)
        .order(ended_at: :desc, started_at: :desc, created_at: :desc)
        .first
    end

    def serialize_command(command_run)
      return if command_run.blank?

      {
        "command_run_public_id" => command_run.public_id,
        "workflow_node_public_id" => command_run.workflow_node&.public_id,
        "tool_invocation_public_id" => command_run.tool_invocation.public_id,
        "cwd" => working_directory_for(command_run.command_line),
        "command_preview" => command_preview_for(command_run.command_line),
        "lifecycle_state" => command_run.lifecycle_state,
        "started_at" => command_run.started_at&.iso8601(6),
        "ended_at" => command_run.ended_at&.iso8601(6),
      }.compact
    end

    def serialize_process(process_run)
      return if process_run.blank?

      {
        "process_run_public_id" => process_run.public_id,
        "workflow_node_public_id" => process_run.workflow_node.public_id,
        "cwd" => working_directory_for(process_run.command_line),
        "command_preview" => command_preview_for(process_run.command_line),
        "lifecycle_state" => process_run.lifecycle_state,
        "started_at" => process_run.started_at&.iso8601(6),
        "ended_at" => process_run.ended_at&.iso8601(6),
      }.compact
    end

    def working_directory_for(command_line)
      command_line.to_s[/\bcd\s+([^\s&;]+)\b/, 1]
    end

    def command_preview_for(command_line)
      command_line.to_s
        .sub(/\A\s*cd\s+[^\s&;]+\s*&&\s*/, "")
        .squish
        .presence
    end
  end
end
