require "test_helper"

class Runtime::Assignments::DispatchModeTest < ActiveSupport::TestCase
  test "defaults to deterministic tool mode when no specialized handler matches" do
    dispatch = Runtime::Assignments::DispatchMode.call(
      task_payload: {},
      runtime_context: {}
    )

    assert_equal "deterministic_tool", dispatch.fetch("kind")
  end

  test "dispatches skill catalog mode through the skills catalog service with a scoped repository" do
    original_catalog_list = Skills::CatalogList.method(:call)
    captured_repository = nil
    Skills::CatalogList.define_singleton_method(:call) do |repository:|
      captured_repository = repository
      "catalog-output"
    end

    dispatch = Runtime::Assignments::DispatchMode.call(
      task_payload: { "mode" => "skills_catalog_list" },
      runtime_context: {
        "agent_id" => "agent-1",
        "user_id" => "user-1",
      }
    )

    assert_equal "skill_flow", dispatch.fetch("kind")
    assert_equal "catalog-output", dispatch.fetch("output")
    assert_equal "agent-1", captured_repository.scope_roots.agent_id
    assert_equal "user-1", captured_repository.scope_roots.user_id
  ensure
    Skills::CatalogList.define_singleton_method(:call, original_catalog_list) if original_catalog_list
  end

  test "dispatches skill load mode with the requested payload" do
    original_load = Skills::Load.method(:call)
    captured_args = nil
    Skills::Load.define_singleton_method(:call) do |skill_name:, repository:|
      captured_args = {
        "skill_name" => skill_name,
        "agent_id" => repository.scope_roots.agent_id,
        "user_id" => repository.scope_roots.user_id,
      }
      "load-output"
    end

    dispatch = Runtime::Assignments::DispatchMode.call(
      task_payload: {
        "mode" => "skills_load",
        "skill_name" => "portable-notes",
      },
      runtime_context: {
        "agent_id" => "agent-1",
        "user_id" => "user-1",
      }
    )

    assert_equal "skill_flow", dispatch.fetch("kind")
    assert_equal "load-output", dispatch.fetch("output")
    assert_equal(
      {
        "skill_name" => "portable-notes",
        "agent_id" => "agent-1",
        "user_id" => "user-1",
      },
      captured_args
    )
  ensure
    Skills::Load.define_singleton_method(:call, original_load) if original_load
  end

  test "dispatches skill read file mode with the requested payload" do
    original_read_file = Skills::ReadFile.method(:call)
    captured_args = nil
    Skills::ReadFile.define_singleton_method(:call) do |skill_name:, relative_path:, repository:|
      captured_args = {
        "skill_name" => skill_name,
        "relative_path" => relative_path,
        "agent_id" => repository.scope_roots.agent_id,
        "user_id" => repository.scope_roots.user_id,
      }
      "read-output"
    end

    dispatch = Runtime::Assignments::DispatchMode.call(
      task_payload: {
        "mode" => "skills_read_file",
        "skill_name" => "portable-notes",
        "relative_path" => "references/checklist.md",
      },
      runtime_context: {
        "agent_id" => "agent-1",
        "user_id" => "user-1",
      }
    )

    assert_equal "skill_flow", dispatch.fetch("kind")
    assert_equal "read-output", dispatch.fetch("output")
    assert_equal(
      {
        "skill_name" => "portable-notes",
        "relative_path" => "references/checklist.md",
        "agent_id" => "agent-1",
        "user_id" => "user-1",
      },
      captured_args
    )
  ensure
    Skills::ReadFile.define_singleton_method(:call, original_read_file) if original_read_file
  end

  test "dispatches skill install mode with the requested payload" do
    original_install = Skills::Install.method(:call)
    captured_args = nil
    Skills::Install.define_singleton_method(:call) do |source_path:, repository:|
      captured_args = {
        "source_path" => source_path,
        "agent_id" => repository.scope_roots.agent_id,
        "user_id" => repository.scope_roots.user_id,
      }
      "install-output"
    end

    dispatch = Runtime::Assignments::DispatchMode.call(
      task_payload: {
        "mode" => "skills_install",
        "source_path" => "/tmp/portable-notes",
      },
      runtime_context: {
        "agent_id" => "agent-1",
        "user_id" => "user-1",
      }
    )

    assert_equal "skill_flow", dispatch.fetch("kind")
    assert_equal "install-output", dispatch.fetch("output")
    assert_equal(
      {
        "source_path" => "/tmp/portable-notes",
        "agent_id" => "agent-1",
        "user_id" => "user-1",
      },
      captured_args
    )
  ensure
    Skills::Install.define_singleton_method(:call, original_install) if original_install
  end
end
