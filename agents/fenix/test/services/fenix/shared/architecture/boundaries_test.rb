require "test_helper"

class FenixSharedArchitectureBoundariesTest < ActiveSupport::TestCase
  test "shared implementation files do not depend on agent or executor namespaces" do
    shared_root = Rails.root.join("app/services/fenix/shared")
    shared_files = Dir.glob(shared_root.join("**/*.rb"))

    assert_predicate shared_files, :any?, "expected shared implementation files to exist"

    offenders = shared_files.filter_map do |path|
      contents = File.read(path)
      next unless contents.match?(/\bFenix::(Agent|Executor)\b/)

      path
    end

    assert_equal [], offenders
  end

  test "agent implementation files do not depend on runtime or legacy namespaces" do
    agent_root = Rails.root.join("app/services/fenix/agent")
    agent_files = Dir.glob(agent_root.join("**/*.rb"))

    assert_predicate agent_files, :any?, "expected agent implementation files to exist"

    offenders = agent_files.filter_map do |path|
      contents = File.read(path)
      next unless contents.match?(/\bFenix::Runtime::|\bFenix::(Prompts|Memory|Hooks|Skills)\b/)

      path
    end

    assert_equal [], offenders
  end

  test "execution runtime implementation files do not depend on runtime or legacy executor namespaces" do
    execution_runtime_root = Rails.root.join("app/services/fenix/execution_runtime")
    execution_runtime_files = Dir.glob(execution_runtime_root.join("**/*.rb"))

    assert_predicate execution_runtime_files, :any?, "expected execution runtime implementation files to exist"

    offenders = execution_runtime_files.filter_map do |path|
      contents = File.read(path)
      next unless contents.match?(/\bFenix::Runtime::|\bFenix::(Processes|Browser|Hooks)\b/)

      path
    end

    assert_equal [], offenders
  end
end
