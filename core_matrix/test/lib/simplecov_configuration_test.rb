require "test_helper"

class SimplecovConfigurationTest < ActiveSupport::TestCase
  test "enables coverage collection for forked parallel workers" do
    assert SimpleCov.enabled_for_subprocesses?,
      "Expected SimpleCov subprocess coverage to be enabled for Rails parallel test workers"
  end

  test "parallel worker setup flushes worker coverage at exit" do
    hook = ActiveSupport::Testing::Parallelization.after_fork_hooks.last

    assert hook, "Expected a parallel worker setup hook to configure SimpleCov"

    original_start = SimpleCov.method(:start)
    original_command_name = SimpleCov.command_name
    original_print_error_status = SimpleCov.print_error_status
    original_formatter = SimpleCov.formatter
    original_minimum_coverage = SimpleCov.minimum_coverage.dup
    original_external_at_exit = SimpleCov.external_at_exit?
    original_coverage_running = Coverage.method(:running?)
    original_coverage_result = Coverage.method(:result)
    start_calls = 0
    coverage_result_calls = []

    SimpleCov.singleton_class.send(:define_method, :start) do |*_, **_kwargs|
      start_calls += 1
      SimpleCov.pid = Process.pid
    end

    SimpleCov.command_name "Minitest"
    SimpleCov.external_at_exit = true

    Coverage.singleton_class.send(:define_method, :running?) do
      true
    end

    Coverage.singleton_class.send(:define_method, :result) do |*args, **kwargs|
      coverage_result_calls << [args, kwargs]
      {}
    end

    hook.call(2)

    assert_equal "Minitest (worker 2)", SimpleCov.command_name
    assert_equal Process.pid, SimpleCov.pid
    assert_equal false, SimpleCov.print_error_status
    assert_equal SimpleCov::Formatter::SimpleFormatter, SimpleCov.formatter
    assert_equal false, SimpleCov.external_at_exit?
    assert_equal({ line: 0 }, SimpleCov.minimum_coverage)
    assert_equal [[[], { stop: false, clear: true }]], coverage_result_calls
    assert_equal 1, start_calls
  ensure
    SimpleCov.singleton_class.send(:define_method, :start, original_start)
    SimpleCov.command_name original_command_name
    SimpleCov.print_error_status = original_print_error_status
    SimpleCov.formatter original_formatter
    SimpleCov.minimum_coverage original_minimum_coverage
    SimpleCov.external_at_exit = original_external_at_exit
    Coverage.singleton_class.send(:define_method, :running?, original_coverage_running)
    Coverage.singleton_class.send(:define_method, :result, original_coverage_result)
  end

  test "groups layered rails directories in the coverage report" do
    expected_groups = %w[Services Queries Resolvers Projections]

    assert_empty expected_groups - SimpleCov.groups.keys
  end

  test "normalizes inherited nil coverage on tracked files back to misses" do
    template = { "lines" => [nil, 0, 0, nil, 0] }
    inherited = { "lines" => [nil, 2, nil, nil, 0] }

    normalized = CoreMatrixSimpleCov.normalize_file_coverage(inherited, template)

    assert_equal [nil, 2, 0, nil, 0], normalized.fetch("lines")
  end

  test "normalizes cached resultset coverage to the current tracked file length" do
    require "tempfile"

    tracked_file = Tempfile.create(["simplecov", ".rb"])
    tracked_file.write("line one\nline two\n")
    tracked_file.flush

    resultset = {
      "Minitest" => {
        "coverage" => {
          tracked_file.path => {
            "lines" => [1, 1, 1],
          },
        },
        "timestamp" => Time.now.to_i,
      },
    }

    original_tracked_files = SimpleCov.method(:tracked_files)
    original_simulate_coverage = SimpleCov::SimulateCoverage.method(:call)

    SimpleCov.singleton_class.send(:define_method, :tracked_files) do
      tracked_file.path
    end

    SimpleCov::SimulateCoverage.singleton_class.send(:define_method, :call) do |_path|
      { "lines" => [0, 0] }
    end

    normalized = CoreMatrixSimpleCov.normalize_resultset_coverage(resultset)

    assert_equal [1, 1], normalized.fetch("Minitest").fetch("coverage").fetch(tracked_file.path).fetch("lines")
  ensure
    if tracked_file
      path = tracked_file.path
      tracked_file.close unless tracked_file.closed?
      File.unlink(path) if path && File.exist?(path)
    end
    SimpleCov.singleton_class.send(:define_method, :tracked_files, original_tracked_files)
    SimpleCov::SimulateCoverage.singleton_class.send(:define_method, :call, original_simulate_coverage)
  end

  test "normalizes source file coverage before simplecov builds lines" do
    require "tempfile"

    tracked_file = Tempfile.create(["simplecov-source", ".rb"])
    tracked_file.write("line one\nline two\n")
    tracked_file.flush

    original_simulate_coverage = SimpleCov::SimulateCoverage.method(:call)

    SimpleCov::SimulateCoverage.singleton_class.send(:define_method, :call) do |_path|
      { "lines" => [0, 0] }
    end

    source_file = SimpleCov::SourceFile.new(
      tracked_file.path,
      { "lines" => [1, 1, 1] }
    )

    assert_equal [1, 1], source_file.coverage_data.fetch("lines")
  ensure
    if tracked_file
      path = tracked_file.path
      tracked_file.close unless tracked_file.closed?
      File.unlink(path) if path && File.exist?(path)
    end
    SimpleCov::SimulateCoverage.singleton_class.send(:define_method, :call, original_simulate_coverage)
  end
end
