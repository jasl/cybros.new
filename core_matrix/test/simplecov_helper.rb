require "coverage"
require "simplecov"

module CoreMatrixSimpleCov
  TEST_SUITE_NAME = "Minitest"

  module_function

  def normalize_tracked_file_coverage(result)
    tracked_files = SimpleCov.tracked_files
    return result unless tracked_files

    Dir[tracked_files].each_with_object(result.dup) do |file, normalized|
      absolute_path = File.expand_path(file)
      template = SimpleCov::SimulateCoverage.call(absolute_path)
      normalized[absolute_path] = normalize_file_coverage(normalized[absolute_path], template)
    end
  end

  def normalize_resultset_coverage(resultset)
    return resultset unless resultset.is_a?(Hash)

    resultset.each_with_object({}) do |(command_name, data), normalized|
      coverage = data.is_a?(Hash) ? data["coverage"] || data[:coverage] : nil
      normalized[command_name] =
        if coverage.is_a?(Hash)
          data.merge("coverage" => normalize_tracked_file_coverage(coverage))
        else
          data
        end
    end
  end

  def normalize_file_coverage(existing, template)
    return template unless existing

    template_lines = template["lines"] || template[:lines]
    existing_lines = existing["lines"] || existing[:lines]

    normalized_lines = template_lines.zip(existing_lines).map do |template_value, existing_value|
      template_value.nil? ? nil : existing_value || 0
    end

    normalized = existing.each_with_object({}) do |(key, value), memo|
      memo[key.to_s] = value
    end

    normalized["lines"] = normalized_lines
    normalized
  end

  def configure_parallel_worker!(worker)
    SimpleCov.command_name "#{TEST_SUITE_NAME} (worker #{worker})"
    SimpleCov.print_error_status = false
    SimpleCov.formatter SimpleCov::Formatter::SimpleFormatter
    SimpleCov.minimum_coverage 0
    SimpleCov.external_at_exit = false
    # Rails forks after boot, so workers inherit the parent's coverage tables.
    # Clear them here and restart SimpleCov state per worker to keep tracked files stable.
    Coverage.result(stop: false, clear: true) if Coverage.running?
    SimpleCov.start
  end
end

module CoreMatrixSimpleCov
  module ResultsetNormalization
    def parse_file(path)
      CoreMatrixSimpleCov.normalize_resultset_coverage(super)
    end
  end

  module ResultNormalization
    private

    def result_with_not_loaded_files
      super

      @result = SimpleCov::Result.new(
        CoreMatrixSimpleCov.normalize_tracked_file_coverage(@result.original_result),
        command_name: @result.command_name,
        created_at: @result.created_at
      )
    end
  end

  module SourceFileNormalization
    def initialize(filename, coverage_data)
      template = SimpleCov::SimulateCoverage.call(filename)
      normalized_coverage =
        if coverage_data.is_a?(Hash)
          CoreMatrixSimpleCov.normalize_file_coverage(coverage_data, template)
        else
          coverage_data
        end

      super(filename, normalized_coverage)
    end
  end
end

SimpleCov::ResultMerger.singleton_class.prepend(CoreMatrixSimpleCov::ResultsetNormalization)
SimpleCov.singleton_class.prepend(CoreMatrixSimpleCov::ResultNormalization)
SimpleCov::SourceFile.prepend(CoreMatrixSimpleCov::SourceFileNormalization)

SimpleCov.enable_for_subprocesses true
SimpleCov.at_fork do |pid|
  SimpleCov.command_name "#{CoreMatrixSimpleCov::TEST_SUITE_NAME} (subprocess: #{pid})"
  SimpleCov.print_error_status = false
  SimpleCov.formatter SimpleCov::Formatter::SimpleFormatter
  SimpleCov.minimum_coverage 0
  SimpleCov.external_at_exit = false
  SimpleCov.start
end

SimpleCov.start "rails" do
  command_name CoreMatrixSimpleCov::TEST_SUITE_NAME
  add_filter "/vendor/"
  add_filter "/script/"
  add_group "Services", "app/services"
  add_group "Queries", "app/queries"
  add_group "Resolvers", "app/resolvers"
  add_group "Projections", "app/projections"
end
