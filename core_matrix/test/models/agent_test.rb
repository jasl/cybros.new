require "test_helper"

class AgentTest < ActiveSupport::TestCase
  test "generates and resolves a public id" do
    agent = create_agent!

    assert agent.public_id.present?
    assert_equal agent, Agent.find_by_public_id!(agent.public_id)
  end

  test "supports global and personal visibility with ownership rules and persists display_name" do
    installation = create_installation!
    owner_user = create_user!(installation: installation)

    global_program = create_agent!(installation: installation, display_name: "Global Support")
    personal_program = create_agent!(
      installation: installation,
      visibility: "personal",
      owner_user: owner_user,
      key: "personal-agent",
      display_name: "Personal Support"
    )

    assert_equal "Global Support", global_program.display_name
    assert global_program.global?
    assert_nil global_program.owner_user

    assert personal_program.personal?
    assert_equal owner_user, personal_program.owner_user

    invalid_personal = Agent.new(
      installation: installation,
      visibility: "personal",
      key: "invalid-personal",
      display_name: "Invalid Personal",
      lifecycle_state: "active"
    )

    assert_not invalid_personal.valid?
    assert_includes invalid_personal.errors[:owner_user], "must exist"
  end

  test "belongs to a default execution runtime from the same installation" do
    installation = create_installation!
    execution_runtime = ExecutionRuntime.create!(
      installation: installation,
      kind: "local",
      display_name: "Executor #{next_test_sequence}",
      execution_runtime_fingerprint: "executor-#{next_test_sequence}",
      connection_metadata: {},
      capability_payload: {},
      tool_catalog: [],
      lifecycle_state: "active"
    )

    agent = Agent.create!(
      installation: installation,
      visibility: "global",
      key: "executor-bound-agent",
      display_name: "Executor Bound Agent",
      lifecycle_state: "active",
      default_execution_runtime: execution_runtime
    )

    assert_equal execution_runtime, agent.default_execution_runtime

    foreign_execution_runtime = ExecutionRuntime.new(
      installation: Installation.new(id: installation.id.to_i + 1, name: "Foreign Installation", bootstrap_state: "bootstrapped", global_settings: {}),
      kind: "local",
      display_name: "Foreign Executor",
      execution_runtime_fingerprint: "foreign-executor-#{next_test_sequence}",
      connection_metadata: {},
      capability_payload: {},
      tool_catalog: [],
      lifecycle_state: "active"
    )

    invalid_program = Agent.new(
      installation: installation,
      visibility: "global",
      key: "invalid-executor-agent",
      display_name: "Invalid Executor Agent",
      lifecycle_state: "active",
      default_execution_runtime: foreign_execution_runtime
    )

    assert_not invalid_program.valid?
    assert_includes invalid_program.errors[:default_execution_runtime], "must belong to the same installation"
  end
end
