require "fileutils"
require "json"
require "tmpdir"
require "uri"

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "core_matrix_cli"

require "minitest/autorun"

class CoreMatrixCLITestCase < Minitest::Test
  def setup
    super
    @tmp_dir = Dir.mktmpdir("core_matrix_cli_test")
  end

  def teardown
    FileUtils.rm_rf(@tmp_dir) if @tmp_dir && File.directory?(@tmp_dir)
    super
  end

  private

  attr_reader :tmp_dir

  def project_root
    File.expand_path("..", __dir__)
  end

  def tmp_path(name)
    File.join(tmp_dir, name)
  end

  def with_env(overrides)
    previous = {}

    overrides.each_key do |key|
      previous[key] = ENV.key?(key) ? ENV[key] : :__missing__
    end

    overrides.each do |key, value|
      value.nil? ? ENV.delete(key) : ENV[key] = value
    end

    yield
  ensure
    previous.each do |key, value|
      value == :__missing__ ? ENV.delete(key) : ENV[key] = value
    end
  end
end
