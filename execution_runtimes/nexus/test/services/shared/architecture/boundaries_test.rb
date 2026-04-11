require "test_helper"

class SharedArchitectureBoundariesTest < ActiveSupport::TestCase
  test "service code no longer references the legacy nexus namespace" do
    files = service_and_runtime_files

    assert_predicate files, :any?, "expected service and runtime files to exist"

    offenders = files.filter_map do |path|
      path if File.read(path).match?(/\bNexus::/)
    end

    assert_equal [], offenders
  end

  test "legacy nexus namespace directories are absent from active code" do
    refute_path_exists Rails.root.join("app/services/nexus")
    refute_path_exists Rails.root.join("app/jobs/nexus")
    refute_path_exists Rails.root.join("lib/nexus")
    refute_path_exists Rails.root.join("test/services/nexus")
  end

  private

  def service_and_runtime_files
    Dir.glob(Rails.root.join("app/services/**/*.rb")) +
      Dir.glob(Rails.root.join("app/jobs/**/*.rb")) +
      Dir.glob(Rails.root.join("app/controllers/**/*.rb")) +
      Dir.glob(Rails.root.join("lib/runtime/**/*.rb")) +
      Dir.glob(Rails.root.join("test/services/**/*.rb"))
  end
end
