require "test_helper"

class ExecutionRuntimeTest < ActiveSupport::TestCase
  test "generates and resolves a public id" do
    execution_runtime = create_execution_runtime!

    assert execution_runtime.public_id.present?
    assert_equal execution_runtime, ExecutionRuntime.find_by_public_id!(execution_runtime.public_id)
  end

  test "supports public and private visibility with provisioning origin invariants" do
    installation = create_installation!
    owner_user = create_user!(installation: installation)

    system_public_runtime = create_execution_runtime!(
      installation: installation,
      visibility: "public",
      provisioning_origin: "system",
      kind: "container",
      display_name: "System Public Runtime"
    )
    user_public_runtime = create_execution_runtime!(
      installation: installation,
      visibility: "public",
      provisioning_origin: "user_created",
      owner_user: owner_user,
      kind: "local",
      display_name: "User Public Runtime"
    )
    user_private_runtime = create_execution_runtime!(
      installation: installation,
      visibility: "private",
      provisioning_origin: "user_created",
      owner_user: owner_user,
      kind: "remote",
      display_name: "User Private Runtime"
    )

    assert system_public_runtime.container?
    assert_equal owner_user, user_public_runtime.owner_user
    assert_equal owner_user, user_private_runtime.owner_user

    invalid_private_ownerless = ExecutionRuntime.new(
      installation: installation,
      visibility: "private",
      provisioning_origin: "user_created",
      kind: "local",
      display_name: "Invalid Private Ownerless Runtime",
      lifecycle_state: "active"
    )
    invalid_user_created_ownerless_public = ExecutionRuntime.new(
      installation: installation,
      visibility: "public",
      provisioning_origin: "user_created",
      kind: "local",
      display_name: "Invalid User Public Runtime",
      lifecycle_state: "active"
    )
    invalid_system_private = ExecutionRuntime.new(
      installation: installation,
      visibility: "private",
      provisioning_origin: "system",
      kind: "local",
      display_name: "Invalid System Private Runtime",
      lifecycle_state: "active"
    )

    assert_not invalid_private_ownerless.valid?
    assert_includes invalid_private_ownerless.errors[:owner_user], "must exist"

    assert_not invalid_user_created_ownerless_public.valid?
    assert_includes invalid_user_created_ownerless_public.errors[:owner_user], "must exist for user-created public visibility"

    assert_not invalid_system_private.valid?
    assert_includes invalid_system_private.errors[:visibility], "must be public for system provisioning"
  end

  test "owner must belong to the same installation" do
    installation = create_installation!
    owner_user = create_user!(installation: installation)
    execution_runtime = create_execution_runtime!(
      installation: installation,
      visibility: "public",
      provisioning_origin: "user_created",
      owner_user: owner_user
    )

    assert_equal owner_user, execution_runtime.owner_user

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
      lifecycle_state: "active"
    )

    assert_not invalid_owner.valid?
    assert_includes invalid_owner.errors[:owner_user], "must belong to the same installation"
  end

  test "tracks the persisted current runtime version and falls back for older rows" do
    execution_runtime = create_execution_runtime!
    runtime_version = create_execution_runtime_version!(execution_runtime: execution_runtime, installation: execution_runtime.installation)

    execution_runtime.update!(
      current_execution_runtime_version: runtime_version,
      published_execution_runtime_version: runtime_version
    )

    assert_equal runtime_version, execution_runtime.published_execution_runtime_version
    assert_equal runtime_version, execution_runtime.current_execution_runtime_version

    execution_runtime.update_columns(current_execution_runtime_version_id: nil)
    assert_equal runtime_version, execution_runtime.reload.current_execution_runtime_version
  end
end
