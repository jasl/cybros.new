require "test_helper"

class ExecutionRuntimeVersionTest < ActiveSupport::TestCase
  test "generates and resolves a public id" do
    runtime_version = create_execution_runtime_version!

    assert runtime_version.public_id.present?
    assert_equal runtime_version, ExecutionRuntimeVersion.find_by_public_id!(runtime_version.public_id)
  end

  test "requires content-fingerprint uniqueness per execution runtime" do
    installation = create_installation!
    execution_runtime = create_execution_runtime!(installation: installation)
    create_execution_runtime_version!(
      installation: installation,
      execution_runtime: execution_runtime,
      content_fingerprint: "runtime-version-a"
    )

    duplicate = build_execution_runtime_version(
      installation: installation,
      execution_runtime: execution_runtime,
      content_fingerprint: "runtime-version-a"
    )

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:content_fingerprint], "has already been taken"
  end
end
