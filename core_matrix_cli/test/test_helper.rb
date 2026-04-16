require "bundler/setup"
require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "json"

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "core_matrix_cli"

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

  def tmp_path(name)
    File.join(tmp_dir, name)
  end
end

FakeShellResult = Struct.new(:success?, :stdout, :stderr, keyword_init: true)

class FakeShellRunner
  attr_reader :commands

  def initialize(results = {})
    @results = results
    @commands = []
  end

  def call(*command)
    @commands << command
    @results.fetch(command) do
      FakeShellResult.new(success?: false, stdout: "", stderr: "unexpected command: #{command.join(' ')}")
    end
  end
end
