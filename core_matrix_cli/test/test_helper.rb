require "fileutils"

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "core_matrix_cli"

require "minitest/autorun"

class Minitest::Test
  private

  def project_root
    File.expand_path("..", __dir__)
  end
end
