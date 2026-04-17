require_relative "../pure_test_helper"

class VerificationLiveSurfaceContractTest < Minitest::Test
  FORBIDDEN_LIVE_REFERENCES = [
    "acceptance/README.md",
    "/Users/jasl/Workspaces/Ruby/cybros/acceptance/",
    "manual_acceptance",
    "Acceptance Harness Integration",
    "active acceptance harness",
    "capstone acceptance harness",
  ].freeze

  def test_live_surface_does_not_reference_removed_acceptance_harness
    scanned_files.each do |path|
      contents = File.read(path)

      FORBIDDEN_LIVE_REFERENCES.each do |pattern|
        refute_includes contents, pattern, "#{path} should not include #{pattern.inspect}"
      end
    end
  end

  def test_verification_test_filenames_do_not_use_from_core_matrix_suffix
    stale_filenames = Dir.glob(
      VerificationPureTestHelper.verification_root.join("test", "**", "*from_core_matrix*").to_s
    )

    assert_empty stale_filenames
  end

  private

  def scanned_files
    @scanned_files ||= begin
      live_targets.flat_map do |target|
        if File.directory?(target)
          Dir.glob(File.join(target, "**", "*")).select { |path| File.file?(path) }
        else
          [target]
        end
      end.reject { |path| File.expand_path(path) == File.expand_path(__FILE__) }
    end
  end

  def live_targets
    repo_root = VerificationPureTestHelper.repo_root
    verification_root = VerificationPureTestHelper.verification_root

    [
      repo_root.join("AGENTS.md").to_s,
      repo_root.join(".github", "workflows", "ci.yml").to_s,
      repo_root.join("core_matrix", "README.md").to_s,
      repo_root.join("images", "nexus", "README.md").to_s,
      repo_root.join("docs", "README.md").to_s,
      repo_root.join("docs", "checklists", "README.md").to_s,
      repo_root.join("docs", "design").to_s,
      repo_root.join("docs", "plans", "README.md").to_s,
      repo_root.join("docs", "reports", "README.md").to_s,
      verification_root.join("README.md").to_s,
      verification_root.join("bin").to_s,
      verification_root.join("lib").to_s,
      verification_root.join("scenarios").to_s,
      verification_root.join("test").to_s,
    ]
  end
end
