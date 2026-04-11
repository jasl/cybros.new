require "test_helper"

class AgentTest < ActiveSupport::TestCase
  test "generates and resolves a public id" do
    installation = create_installation!
    agent = Agent.create!(
      installation: installation,
      visibility: "public",
      provisioning_origin: "system",
      key: "shared-agent",
      display_name: "Shared Agent",
      lifecycle_state: "active"
    )

    assert agent.public_id.present?
    assert_equal agent, Agent.find_by_public_id!(agent.public_id)
  end

  test "supports public and private visibility with provisioning origin invariants" do
    installation = create_installation!
    owner_user = create_user!(installation: installation)

    system_public_agent = Agent.create!(
      installation: installation,
      visibility: "public",
      provisioning_origin: "system",
      key: "system-public-agent",
      display_name: "System Public Agent",
      lifecycle_state: "active"
    )
    user_public_agent = Agent.create!(
      installation: installation,
      visibility: "public",
      provisioning_origin: "user_created",
      owner_user: owner_user,
      key: "user-public-agent",
      display_name: "User Public Agent",
      lifecycle_state: "active"
    )
    user_private_agent = Agent.create!(
      installation: installation,
      visibility: "private",
      provisioning_origin: "user_created",
      owner_user: owner_user,
      key: "user-private-agent",
      display_name: "User Private Agent",
      lifecycle_state: "active"
    )

    assert_equal "System Public Agent", system_public_agent.display_name
    assert Agent.visibilities.key?("public")
    assert Agent.visibilities.key?("private")
    assert_equal "system", system_public_agent.provisioning_origin
    assert_equal owner_user, user_public_agent.owner_user
    assert_equal owner_user, user_private_agent.owner_user

    invalid_private_ownerless = Agent.new(
      installation: installation,
      visibility: "private",
      provisioning_origin: "user_created",
      key: "invalid-private-ownerless",
      display_name: "Invalid Private Ownerless",
      lifecycle_state: "active"
    )
    invalid_user_created_ownerless_public = Agent.new(
      installation: installation,
      visibility: "public",
      provisioning_origin: "user_created",
      key: "invalid-user-created-ownerless-public",
      display_name: "Invalid User Public",
      lifecycle_state: "active"
    )
    invalid_system_private = Agent.new(
      installation: installation,
      visibility: "private",
      provisioning_origin: "system",
      key: "invalid-system-private",
      display_name: "Invalid System Private",
      lifecycle_state: "active"
    )

    assert_not invalid_private_ownerless.valid?
    assert_includes invalid_private_ownerless.errors[:owner_user], "must exist"

    assert_not invalid_user_created_ownerless_public.valid?
    assert_includes invalid_user_created_ownerless_public.errors[:owner_user], "must exist for user-created public visibility"

    assert_not invalid_system_private.valid?
    assert_includes invalid_system_private.errors[:visibility], "must be public for system provisioning"
  end

  test "owner and default execution runtime must belong to the same installation" do
    installation = create_installation!
    owner_user = create_user!(installation: installation)
    execution_runtime = ExecutionRuntime.create!(
      installation: installation,
      visibility: "public",
      provisioning_origin: "system",
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
      visibility: "public",
      provisioning_origin: "user_created",
      owner_user: owner_user,
      key: "runtime-bound-agent",
      display_name: "Runtime Bound Agent",
      lifecycle_state: "active",
      default_execution_runtime: execution_runtime
    )

    assert_equal execution_runtime, agent.default_execution_runtime

    foreign_installation = Installation.new(
      id: installation.id.to_i + 1,
      name: "Foreign Installation",
      bootstrap_state: "bootstrapped",
      global_settings: {}
    )
    foreign_owner = User.new(
      installation: foreign_installation,
      identity: create_identity!,
      role: "member",
      display_name: "Foreign Owner",
      preferences: {}
    )
    foreign_execution_runtime = ExecutionRuntime.new(
      installation: foreign_installation,
      visibility: "public",
      provisioning_origin: "system",
      kind: "local",
      display_name: "Foreign Executor",
      execution_runtime_fingerprint: "foreign-executor-#{next_test_sequence}",
      connection_metadata: {},
      capability_payload: {},
      tool_catalog: [],
      lifecycle_state: "active"
    )

    invalid_owner = Agent.new(
      installation: installation,
      visibility: "private",
      provisioning_origin: "user_created",
      owner_user: foreign_owner,
      key: "invalid-owner-agent",
      display_name: "Invalid Owner Agent",
      lifecycle_state: "active"
    )
    invalid_runtime = Agent.new(
      installation: installation,
      visibility: "public",
      provisioning_origin: "user_created",
      owner_user: owner_user,
      key: "invalid-runtime-agent",
      display_name: "Invalid Runtime Agent",
      lifecycle_state: "active",
      default_execution_runtime: foreign_execution_runtime
    )

    assert_not invalid_owner.valid?
    assert_includes invalid_owner.errors[:owner_user], "must belong to the same installation"

    assert_not invalid_runtime.valid?
    assert_includes invalid_runtime.errors[:default_execution_runtime], "must belong to the same installation"
  end
end
