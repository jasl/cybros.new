module CommandRuns
  class Provision
    Result = Struct.new(:command_run, :created, keyword_init: true)

    def self.call(...)
      new(...).call
    end

    def initialize(tool_invocation:, command_line:, timeout_seconds: nil, pty: false, metadata: {})
      @tool_invocation = tool_invocation
      @command_line = command_line
      @timeout_seconds = timeout_seconds
      @pty = pty
      @metadata = metadata
    end

    def call
      @tool_invocation.with_lock do
        existing = @tool_invocation.command_run
        return Result.new(command_run: existing, created: false) if existing.present?

        command_run = CommandRun.create!(
          installation: @tool_invocation.installation,
          user: @tool_invocation.user,
          workspace: @tool_invocation.workspace,
          agent: @tool_invocation.agent,
          agent_task_run: @tool_invocation.agent_task_run,
          conversation: @tool_invocation.conversation,
          turn: @tool_invocation.turn,
          workflow_run: @tool_invocation.workflow_run,
          workflow_node: @tool_invocation.workflow_node,
          tool_invocation: @tool_invocation,
          lifecycle_state: "starting",
          command_line: @command_line,
          timeout_seconds: @timeout_seconds,
          pty: @pty,
          metadata: @metadata
        )

        Result.new(command_run: command_run, created: true)
      end
    end
  end
end
