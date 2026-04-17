require "fileutils"
require "tmpdir"

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "cybros_nexus"
require "minitest/autorun"

module TemporaryPaths
  def tmp_path(relative_path)
    path = File.join(tmp_root, relative_path)
    FileUtils.mkdir_p(File.dirname(path))
    path
  end

  def teardown
    super
    FileUtils.remove_entry(tmp_root) if defined?(@tmp_root) && @tmp_root && File.exist?(@tmp_root)
  end

  private

  def tmp_root
    @tmp_root ||= Dir.mktmpdir("cybros_nexus_test")
  end
end

class Minitest::Test
  include TemporaryPaths
end
