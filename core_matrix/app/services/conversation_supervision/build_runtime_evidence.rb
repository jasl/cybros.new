module ConversationSupervision
  class BuildRuntimeEvidence
    ACTIVE_COMMAND_STATES = %w[starting running].freeze
    ACTIVE_PROCESS_STATES = %w[starting running].freeze
    ACTIVE_TOOL_NODE_STATES = %w[pending queued running waiting].freeze
    TERMINAL_COMMAND_STATES = %w[completed failed interrupted canceled].freeze
    TERMINAL_PROCESS_STATES = %w[stopped failed lost].freeze
    TERMINAL_TOOL_NODE_STATES = %w[completed failed canceled].freeze

    def self.call(...)
      new(...).call
    end

    def initialize(conversation:, workflow_run: nil)
      @conversation = conversation
      @workflow_run = workflow_run
    end

    def call
      {
        "active_tool_call" => active_tool_call,
        "recent_tool_call" => recent_tool_call,
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

      @workflow_run = if @conversation.latest_active_workflow_run&.active?
        @conversation.latest_active_workflow_run
      else
        @conversation.workflow_runs.order(created_at: :desc).first
      end
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

    def tool_call_nodes
      @tool_call_nodes ||= if workflow_run.present?
        workflow_run.workflow_nodes
          .where(node_type: "tool_call")
          .includes(:tool_call_document, :command_runs, :process_runs)
      else
        WorkflowNode.none
      end
    end

    def current_turn_step_node
      return @current_turn_step_node if instance_variable_defined?(:@current_turn_step_node)

      @current_turn_step_node = if workflow_run.present?
        workflow_run.workflow_nodes
          .where(node_type: "turn_step", lifecycle_state: ACTIVE_TOOL_NODE_STATES)
          .order(started_at: :desc, created_at: :desc)
          .first
      end
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

    def active_tool_call
      serialize_tool_call_node(active_tool_call_node) || serialize_runtime_tool_call_event(active_runtime_tool_call_event)
    end

    def recent_tool_call
      serialize_tool_call_node(recent_tool_call_node) || serialize_runtime_tool_call_event(recent_runtime_tool_call_event)
    end

    def active_tool_call_node
      return @active_tool_call_node if instance_variable_defined?(:@active_tool_call_node)

      @active_tool_call_node = tool_call_nodes
        .where(lifecycle_state: ACTIVE_TOOL_NODE_STATES)
        .order(started_at: :desc, created_at: :desc)
        .first
    end

    def recent_tool_call_node
      return @recent_tool_call_node if instance_variable_defined?(:@recent_tool_call_node)

      @recent_tool_call_node = tool_call_nodes
        .where.not(id: active_tool_call_node&.id)
        .where(lifecycle_state: TERMINAL_TOOL_NODE_STATES)
        .order(finished_at: :desc, started_at: :desc, created_at: :desc)
        .first
    end

    def runtime_tool_call_events
      return @runtime_tool_call_events if instance_variable_defined?(:@runtime_tool_call_events)

      @runtime_tool_call_events =
        if workflow_run.present?
          ConversationEvent
            .where(conversation: @conversation, turn: workflow_run.turn)
            .where(event_kind: ["runtime.assistant_tool_call.delta", "runtime.assistant_tool_call.completed"])
            .order(projection_sequence: :desc)
            .limit(16)
            .to_a
        else
          []
        end
    end

    def active_runtime_tool_call_event
      return @active_runtime_tool_call_event if instance_variable_defined?(:@active_runtime_tool_call_event)

      node_id = current_turn_step_node&.public_id
      @active_runtime_tool_call_event =
        if node_id.present?
          runtime_tool_call_events.find do |event|
            event.payload["workflow_node_id"] == node_id
          end
        end
    end

    def recent_runtime_tool_call_event
      return @recent_runtime_tool_call_event if instance_variable_defined?(:@recent_runtime_tool_call_event)

      @recent_runtime_tool_call_event = runtime_tool_call_events.find do |event|
        event.event_kind == "runtime.assistant_tool_call.completed"
      end
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

    def serialize_tool_call_node(node)
      return if node.blank?

      payload = node.tool_call_payload.to_h.deep_stringify_keys
      command_run = node.command_runs.max_by { |run| [run.started_at || Time.at(0), run.created_at] }
      command_run ||= referenced_command_run_for(payload)
      process_run = node.process_runs.max_by { |run| [run.started_at || Time.at(0), run.created_at] }
      command_line =
        command_run&.command_line ||
        process_run&.command_line ||
        payload.dig("request_payload", "arguments", "command_line") ||
        payload.dig("arguments", "command_line") ||
        payload["command_line"]
      cwd = working_directory_for(command_line)
      command_preview = command_preview_for(command_line)

      {
        "source_kind" => "workflow_node",
        "workflow_node_public_id" => node.public_id,
        "provider_round_index" => node.provider_round_index,
        "tool_name" => payload["tool_name"],
        "cwd" => cwd,
        "command_preview" => command_preview,
        "lifecycle_state" => node.lifecycle_state,
        "started_at" => node.started_at&.iso8601(6),
        "ended_at" => node.finished_at&.iso8601(6),
        "summary" => summarize_tool_call(
          tool_name: payload["tool_name"],
          lifecycle_state: node.lifecycle_state,
          payload: payload,
          cwd: cwd,
          command_preview: command_preview,
          command_run: command_run,
          process_run: process_run
        ),
      }.compact
    end

    def referenced_command_run_for(payload)
      command_run_id =
        payload["command_run_public_id"].presence ||
        payload.dig("request_payload", "arguments", "command_run_id").presence ||
        payload.dig("arguments", "command_run_id").presence
      return if command_run_id.blank?

      command_runs.find_by(public_id: command_run_id)
    end

    def serialize_runtime_tool_call_event(event)
      return if event.blank?

      payload = event.payload.deep_stringify_keys
      {
        "source_kind" => "runtime_event",
        "workflow_node_public_id" => payload["workflow_node_id"],
        "provider_round_index" => payload["provider_round_index"],
        "tool_name" => payload["tool_name"],
        "cwd" => payload["cwd"],
        "command_preview" => payload["command_preview"],
        "lifecycle_state" => payload["lifecycle_state"],
        "started_at" => event.created_at&.iso8601(6),
        "summary" => payload["summary"],
      }.compact
    end

    def summarize_tool_call(tool_name:, lifecycle_state:, payload:, cwd:, command_preview:, command_run:, process_run:)
      case tool_name.to_s
      when "command_run_wait"
        command_summary = payload["command_summary"].presence || payload.dig("request_payload", "arguments", "command_summary").presence
        return "Waiting for #{command_summary}" if command_summary.present?
        return "Waiting for a running shell command in #{cwd}" if cwd.present?

        "Waiting for a running shell command"
      when "exec_command"
        summarize_command_tool_call(lifecycle_state:, cwd:, command_preview:, command_run:)
      when "process_exec"
        summarize_process_tool_call(lifecycle_state:, cwd:, command_preview:, process_run:)
      when "subagent_spawn"
        lifecycle_state.in?(TERMINAL_TOOL_NODE_STATES) ? "Prepared a child task request." : "Preparing a child task"
      else
        lifecycle_state.in?(TERMINAL_TOOL_NODE_STATES) ? "Prepared a tool call." : "Preparing a tool call"
      end
    end

    def summarize_command_tool_call(lifecycle_state:, cwd:, command_preview:, command_run:)
      state = command_run&.lifecycle_state.presence || lifecycle_state.to_s

      case state
      when "failed", "canceled", "interrupted"
        "A shell command failed#{location_phrase("cwd" => cwd)}."
      when "completed"
        "A shell command finished#{location_phrase("cwd" => cwd)}."
      else
        return "Running shell command #{command_preview} in #{cwd}" if cwd.present? && command_preview.present?
        return "Running a shell command in #{cwd}" if cwd.present?

        "Running a shell command"
      end
    end

    def summarize_process_tool_call(lifecycle_state:, cwd:, command_preview:, process_run:)
      state = process_run&.lifecycle_state.presence || lifecycle_state.to_s

      case state
      when "failed", "lost"
        "A process failed#{location_phrase("cwd" => cwd)}."
      when "completed", "stopped"
        "A process finished#{location_phrase("cwd" => cwd)}."
      else
        return "Running process #{command_preview} in #{cwd}" if cwd.present? && command_preview.present?
        return "Running a process in #{cwd}" if cwd.present?

        "Running a process"
      end
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

    def location_phrase(payload)
      cwd = payload.to_h["cwd"].presence
      return "" if cwd.blank?

      " in #{cwd}"
    end
  end
end
