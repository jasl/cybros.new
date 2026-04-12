require "test_helper"

module Workbench
end

class Workbench::CreateConversationFromAgentTest < ActiveSupport::TestCase
  test "enables the agent materializes the default workspace and creates the first user turn" do
    installation = create_installation!
    user = create_user!(installation: installation)
    execution_runtime = create_execution_runtime!(installation: installation)
    create_execution_runtime_connection!(installation: installation, execution_runtime: execution_runtime)
    agent = create_agent!(
      installation: installation,
      visibility: "public",
      default_execution_runtime: execution_runtime
    )
    create_agent_connection!(installation: installation, agent: agent)

    result = nil

    assert_difference(["UserAgentBinding.count", "Workspace.count", "Conversation.count", "Turn.count", "Message.count"], +1) do
      result = Workbench::CreateConversationFromAgent.call(
        user: user,
        agent: agent,
        content: "Help me start"
      )
    end

    assert_equal user, result.workspace.user
    assert_equal agent, result.conversation.agent
    assert result.workspace.is_default?
    assert_equal "Help me start", result.message.content
    assert_equal result.conversation, result.turn.conversation
  end
end
