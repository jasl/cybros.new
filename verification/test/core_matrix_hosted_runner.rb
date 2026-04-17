require_relative "manifest"

Verification::TestManifest.absolute_paths(Verification::TestManifest::CORE_MATRIX_HOSTED_TEST_FILES).each do |path|
  require path
end
