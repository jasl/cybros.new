module ProviderExecution
  class AssistantToolCallStream
    def initialize(workflow_node:)
      @workflow_node = workflow_node
      @workflow_run = workflow_node.workflow_run
      @conversation = workflow_node.conversation
      @turn = workflow_node.turn
      @states = {}
    end

    def record(event)
      case event
      when SimpleInference::Responses::Events::ToolCallDelta
        record_delta(event)
      when SimpleInference::Responses::Events::ToolCallDone
        record_done(event)
      end
    end

    private

    def record_delta(event)
      state = state_for(event)
      state[:tool_name] ||= event.name
      state[:arguments] << event.delta.to_s
      payload = build_payload(state:, lifecycle_state: "running")
      signature = emission_signature(payload)
      return if state[:last_signature] == signature

      state[:last_signature] = signature
      publish!("runtime.assistant_tool_call.delta", payload)
    end

    def record_done(event)
      state = state_for(event)
      state[:tool_name] ||= event.name
      state[:arguments] = event.arguments.to_s
      publish!("runtime.assistant_tool_call.completed", build_payload(state:, lifecycle_state: "completed"))
    end

    def state_for(event)
      key = tool_call_key(event)
      @states[key] ||= {
        key: key,
        item_id: event.item_id,
        call_id: event.call_id,
        tool_name: event.name,
        arguments: +"",
      }
    end

    def tool_call_key(event)
      event.call_id.presence || event.item_id
    end

    def build_payload(state:, lifecycle_state:)
      arguments = parse_arguments(state[:arguments])
      tool_name = state[:tool_name].to_s
      command_line = arguments["command_line"].presence || arguments["cmd"].presence || arguments["command"].presence
      cwd = working_directory_for(command_line)
      command_preview = command_preview_for(command_line)
      summary = summarize_tool_call(
        tool_name: tool_name,
        lifecycle_state: lifecycle_state,
        arguments: arguments,
        cwd: cwd,
        command_preview: command_preview
      )

      {
        "stream_id" => "assistant-tool-call:#{@workflow_node.public_id}:#{state[:key]}",
        "workflow_run_id" => @workflow_run.public_id,
        "workflow_node_id" => @workflow_node.public_id,
        "provider_round_index" => @workflow_node.provider_round_index,
        "item_id" => state[:item_id],
        "call_id" => state[:call_id],
        "tool_name" => tool_name.presence,
        "cwd" => cwd,
        "command_preview" => command_preview,
        "summary" => summary,
        "lifecycle_state" => lifecycle_state,
      }.compact
    end

    def summarize_tool_call(tool_name:, lifecycle_state:, arguments:, cwd:, command_preview:)
      case tool_name
      when "exec_command"
        prefix = lifecycle_state == "completed" ? "Prepared a shell command" : "Preparing a shell command"
        return "#{prefix} in #{cwd}" if cwd.present?
        return "#{prefix}: #{command_preview}" if command_preview.present?

        prefix
      when "command_run_wait"
        command_summary = arguments["command_summary"].presence
        return "Waiting for #{command_summary}" if command_summary.present?
        return "Waiting for a running shell command in #{cwd}" if cwd.present?

        "Waiting for a running shell command"
      when "subagent_spawn"
        lifecycle_state == "completed" ? "Prepared a child task request" : "Preparing a child task"
      when "process_exec"
        prefix = lifecycle_state == "completed" ? "Prepared a process launch" : "Preparing a process launch"
        return "#{prefix} in #{cwd}" if cwd.present?
        return "#{prefix}: #{command_preview}" if command_preview.present?

        prefix
      else
        lifecycle_state == "completed" ? "Prepared a tool call" : "Preparing a tool call"
      end
    end

    def parse_arguments(raw)
      JSON.parse(raw.to_s)
    rescue JSON::ParserError
      {
        "command_line" => extract_json_string(raw, "command_line"),
        "command_summary" => extract_json_string(raw, "command_summary"),
      }.compact
    end

    def extract_json_string(raw, key)
      match = raw.to_s.match(/"#{Regexp.escape(key)}"\s*:\s*"([^"]*)/)
      match && match[1]
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

    def emission_signature(payload)
      payload.slice("tool_name", "cwd", "command_preview", "summary", "lifecycle_state").to_a
    end

    def publish!(event_kind, payload)
      ConversationRuntime::PublishEvent.call(
        conversation: @conversation,
        turn: @turn,
        event_kind: event_kind,
        payload: payload,
        progress_dispatcher: ChannelDeliveries::DispatchRuntimeProgress
      )
    end
  end
end
