require "test_helper"

class Fenix::Runtime::Assignments::DispatchModeTest < ActiveSupport::TestCase
  test "defaults to deterministic tool mode when no specialized handler matches" do
    dispatch = Fenix::Runtime::Assignments::DispatchMode.call(task_payload: {})

    assert_equal "deterministic_tool", dispatch.fetch("kind")
  end

  test "dispatches skill catalog mode through the skills catalog service" do
    original_catalog_list = Fenix::Skills::CatalogList.method(:call)
    Fenix::Skills::CatalogList.define_singleton_method(:call) { "catalog-output" }

    dispatch = Fenix::Runtime::Assignments::DispatchMode.call(
      task_payload: { "mode" => "skills_catalog_list" }
    )

    assert_equal "skill_flow", dispatch.fetch("kind")
    assert_equal "catalog-output", dispatch.fetch("output")
  ensure
    Fenix::Skills::CatalogList.define_singleton_method(:call, original_catalog_list) if original_catalog_list
  end

  test "dispatches skill read file mode with the requested payload" do
    original_read_file = Fenix::Skills::ReadFile.method(:call)
    captured_args = nil
    Fenix::Skills::ReadFile.define_singleton_method(:call) do |skill_name:, relative_path:|
      captured_args = { "skill_name" => skill_name, "relative_path" => relative_path }
      "read-output"
    end

    dispatch = Fenix::Runtime::Assignments::DispatchMode.call(
      task_payload: {
        "mode" => "skills_read_file",
        "skill_name" => "example-skill",
        "relative_path" => "README.md",
      }
    )

    assert_equal "skill_flow", dispatch.fetch("kind")
    assert_equal "read-output", dispatch.fetch("output")
    assert_equal(
      {
        "skill_name" => "example-skill",
        "relative_path" => "README.md",
      },
      captured_args
    )
  ensure
    Fenix::Skills::ReadFile.define_singleton_method(:call, original_read_file) if original_read_file
  end

  test "leaves raise_error mode to the caller" do
    dispatch = Fenix::Runtime::Assignments::DispatchMode.call(
      task_payload: { "mode" => "raise_error" }
    )

    assert_equal "raise_error", dispatch.fetch("kind")
  end
end
