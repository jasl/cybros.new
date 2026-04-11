require "test_helper"

class ExecutionRuntimeTest < ActiveSupport::TestCase
  test "generates and resolves a public id" do
    installation = create_installation!
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

    assert execution_runtime.public_id.present?
    assert_equal execution_runtime, ExecutionRuntime.find_by_public_id!(execution_runtime.public_id)
  end

  test "supports public and private visibility with provisioning origin invariants" do
    installation = create_installation!
    owner_user = create_user!(installation: installation)

    system_public_runtime = ExecutionRuntime.create!(
      installation: installation,
      visibility: "public",
      provisioning_origin: "system",
      kind: "container",
      display_name: "System Public Runtime",
      execution_runtime_fingerprint: "system-public-runtime",
      connection_metadata: {
        "transport" => "http",
        "base_url" => "https://runtime.example.test",
      },
      capability_payload: {},
      tool_catalog: [],
      lifecycle_state: "active"
    )
    user_public_runtime = ExecutionRuntime.create!(
      installation: installation,
      visibility: "public",
      provisioning_origin: "user_created",
      owner_user: owner_user,
      kind: "local",
      display_name: "User Public Runtime",
      execution_runtime_fingerprint: "user-public-runtime",
      connection_metadata: {},
      capability_payload: {},
      tool_catalog: [],
      lifecycle_state: "active"
    )
    user_private_runtime = ExecutionRuntime.create!(
      installation: installation,
      visibility: "private",
      provisioning_origin: "user_created",
      owner_user: owner_user,
      kind: "remote",
      display_name: "User Private Runtime",
      execution_runtime_fingerprint: "user-private-runtime",
      connection_metadata: {},
      capability_payload: {},
      tool_catalog: [],
      lifecycle_state: "active"
    )

    assert system_public_runtime.container?
    assert_equal "https://runtime.example.test", system_public_runtime.connection_metadata["base_url"]
    assert_equal owner_user, user_public_runtime.owner_user
    assert_equal owner_user, user_private_runtime.owner_user

    invalid_private_ownerless = ExecutionRuntime.new(
      installation: installation,
      visibility: "private",
      provisioning_origin: "user_created",
      kind: "local",
      display_name: "Invalid Private Ownerless Runtime",
      execution_runtime_fingerprint: "invalid-private-ownerless-runtime",
      connection_metadata: {},
      capability_payload: {},
      tool_catalog: [],
      lifecycle_state: "active"
    )
    invalid_user_created_ownerless_public = ExecutionRuntime.new(
      installation: installation,
      visibility: "public",
      provisioning_origin: "user_created",
      kind: "local",
      display_name: "Invalid User Public Runtime",
      execution_runtime_fingerprint: "invalid-user-created-ownerless-public-runtime",
      connection_metadata: {},
      capability_payload: {},
      tool_catalog: [],
      lifecycle_state: "active"
    )
    invalid_system_private = ExecutionRuntime.new(
      installation: installation,
      visibility: "private",
      provisioning_origin: "system",
      kind: "local",
      display_name: "Invalid System Private Runtime",
      execution_runtime_fingerprint: "invalid-system-private-runtime",
      connection_metadata: {},
      capability_payload: {},
      tool_catalog: [],
      lifecycle_state: "active"
    )

    assert_not invalid_private_ownerless.valid?
    assert_includes invalid_private_ownerless.errors[:owner_user], "must exist"

    assert_not invalid_user_created_ownerless_public.valid?
    assert_includes invalid_user_created_ownerless_public.errors[:owner_user], "must exist for user-created public visibility"

    assert_not invalid_system_private.valid?
    assert_includes invalid_system_private.errors[:visibility], "must be public for system provisioning"
  end

  test "requires installation-local ownership, unique fingerprints, and valid payload hashes" do
    installation = create_installation!
    owner_user = create_user!(installation: installation)
    ExecutionRuntime.create!(
      installation: installation,
      visibility: "public",
      provisioning_origin: "user_created",
      owner_user: owner_user,
      kind: "local",
      display_name: "Runtime A",
      execution_runtime_fingerprint: "runtime-a",
      connection_metadata: {},
      capability_payload: { "supports_process_runs" => true },
      tool_catalog: [],
      lifecycle_state: "active"
    )

    duplicate = ExecutionRuntime.new(
      installation: installation,
      visibility: "public",
      provisioning_origin: "user_created",
      owner_user: owner_user,
      kind: "local",
      display_name: "Duplicate Runtime",
      execution_runtime_fingerprint: "runtime-a",
      connection_metadata: {},
      capability_payload: {},
      tool_catalog: [],
      lifecycle_state: "active"
    )
    invalid_connection_metadata = ExecutionRuntime.new(
      installation: installation,
      visibility: "public",
      provisioning_origin: "user_created",
      owner_user: owner_user,
      kind: "local",
      display_name: "Invalid Connection Metadata Runtime",
      execution_runtime_fingerprint: "runtime-b",
      connection_metadata: [],
      capability_payload: {},
      tool_catalog: [],
      lifecycle_state: "active"
    )
    invalid_payload = ExecutionRuntime.new(
      installation: installation,
      visibility: "public",
      provisioning_origin: "user_created",
      owner_user: owner_user,
      kind: "local",
      display_name: "Invalid Payload Runtime",
      execution_runtime_fingerprint: "runtime-c",
      connection_metadata: {},
      capability_payload: [],
      tool_catalog: [],
      lifecycle_state: "active"
    )

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
    invalid_owner = ExecutionRuntime.new(
      installation: installation,
      visibility: "private",
      provisioning_origin: "user_created",
      owner_user: foreign_owner,
      kind: "local",
      display_name: "Invalid Owner Runtime",
      execution_runtime_fingerprint: "runtime-d",
      connection_metadata: {},
      capability_payload: {},
      tool_catalog: [],
      lifecycle_state: "active"
    )

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:execution_runtime_fingerprint], "has already been taken"

    assert_not invalid_connection_metadata.valid?
    assert_includes invalid_connection_metadata.errors[:connection_metadata], "must be a Hash"

    assert_not invalid_payload.valid?
    assert_includes invalid_payload.errors[:capability_payload], "must be a Hash"

    assert_not invalid_owner.valid?
    assert_includes invalid_owner.errors[:owner_user], "must belong to the same installation"
  end
end
