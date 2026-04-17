require "fileutils"
require "json"
require "tmpdir"
require "uri"
require "stringio"

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "core_matrix_cli"

require "minitest/autorun"
require_relative "support/fake_core_matrix_api"
require_relative "support/fake_browser_launcher"
require_relative "support/fake_qr_renderer"

class TestInput < StringIO
  def noecho
    yield self
  end
end

class NonTtyInput < StringIO
  def noecho
    raise Errno::ENOTTY, "not a tty"
  end
end

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

  def with_cli_factory(name, value)
    previous = CoreMatrixCLI.public_send(name)
    CoreMatrixCLI.public_send("#{name}=", value.respond_to?(:call) ? value : -> { value })
    yield
  ensure
    CoreMatrixCLI.public_send("#{name}=", previous)
  end

  def run_cli(*args, input: "", api: FakeCoreMatrixAPI.new, config_repository: nil, credential_repository: nil, browser_launcher: FakeBrowserLauncher.new, qr_renderer: FakeQrRenderer.new, input_io: nil)
    config_repository ||= CoreMatrixCLI::State::ConfigRepository.new(path: tmp_path("config.json"))
    credential_repository ||= CoreMatrixCLI::CredentialStores::FileStore.new(path: tmp_path("credentials.json"))

    stdin = $stdin
    $stdin = input_io || TestInput.new(input)

    output = nil
    with_cli_factory(:config_repository_factory, -> { config_repository }) do
      with_cli_factory(:credential_repository_factory, -> { credential_repository }) do
        with_cli_factory(:api_factory, ->(**) { api }) do
          with_cli_factory(:browser_launcher_factory, -> { browser_launcher }) do
            with_cli_factory(:qr_renderer_factory, -> { qr_renderer }) do
              stdout, stderr = capture_io do
                CoreMatrixCLI::CLI.start(args.flatten.map(&:to_s))
              end
              output = stdout + stderr
            end
          end
        end
      end
    end

    output
  ensure
    $stdin = stdin
  end
end
