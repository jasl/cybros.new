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

  def with_dir_home(path)
    with_stubbed_singleton_method(Dir, :home, -> { path }) do
      yield
    end
  end

  def with_stubbed_singleton_method(object, method_name, replacement)
    singleton = object.singleton_class
    alias_name = :"__codex_original_#{method_name}_#{object.object_id}_#{rand(1_000_000)}"

    singleton.class_eval do
      alias_method alias_name, method_name
      remove_method method_name
      define_method(method_name, &replacement)
    end

    yield
  ensure
    singleton.class_eval do
      remove_method method_name
      alias_method method_name, alias_name
      remove_method alias_name
    end
  end
end
