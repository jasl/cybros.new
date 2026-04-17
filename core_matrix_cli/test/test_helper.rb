require "bundler/setup"
require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "json"
require "stringio"

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "core_matrix_cli"
require_relative "support/fake_core_matrix_server"

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

  def tmp_path(name)
    File.join(tmp_dir, name)
  end

  def with_runtime_factory(runtime)
    previous_runtime_factory = CoreMatrixCLI.runtime_factory
    CoreMatrixCLI.runtime_factory = runtime.respond_to?(:call) ? runtime : -> { runtime }
    yield
  ensure
    CoreMatrixCLI.runtime_factory = previous_runtime_factory
  end

  def with_browser_launcher_factory(browser_launcher)
    previous_browser_launcher_factory = CoreMatrixCLI.browser_launcher_factory
    CoreMatrixCLI.browser_launcher_factory = -> { browser_launcher }
    yield
  ensure
    CoreMatrixCLI.browser_launcher_factory = previous_browser_launcher_factory
  end

  def with_env(overrides)
    previous = overrides.transform_values { |_,| nil }
    overrides.each_key do |key|
      previous[key] = ENV.key?(key) ? ENV[key] : :__missing__
    end

    overrides.each do |key, value|
      value.nil? ? ENV.delete(key) : ENV[key] = value
    end

    yield
  ensure
    previous&.each do |key, value|
      value == :__missing__ ? ENV.delete(key) : ENV[key] = value
    end
  end

  def run_cli(*args, input: "", runtime:, browser_launcher: FakeBrowserLauncher.new, input_io: nil)
    output = nil
    stdin = $stdin
    $stdin = input_io || TestInput.new(input)

    with_runtime_factory(runtime) do
      with_browser_launcher_factory(browser_launcher) do
        stdout, stderr = capture_io do
          CoreMatrixCLI::CLI.start(args.flatten.map(&:to_s))
        end
        output = stdout + stderr
      end
    end

    output
  ensure
    $stdin = stdin
  end
end

class FakeRuntime
  attr_reader :calls, :config_store, :credential_store
  attr_accessor :bootstrap_status_payload, :bootstrap_response, :login_response,
    :session_response, :logout_response, :readiness_payload, :workspaces_response,
    :create_workspace_response, :agents_response, :attach_workspace_agent_response,
    :start_codex_authorization_response, :codex_authorization_status_sequence,
    :poll_codex_authorization_sequence,
    :revoke_codex_authorization_response, :create_ingress_binding_responses,
    :update_ingress_binding_responses, :weixin_start_login_response,
    :weixin_login_status_sequence

  def initialize(config_store:, credential_store:)
    @config_store = config_store
    @credential_store = credential_store
    @calls = []
    @bootstrap_status_payload = { "bootstrap_state" => "bootstrapped" }
    @bootstrap_response = nil
    @login_response = nil
    @session_response = nil
    @logout_response = { "ok" => true }
    @readiness_payload = {}
    @workspaces_response = { "workspaces" => [] }
    @create_workspace_response = nil
    @agents_response = { "agents" => [] }
    @attach_workspace_agent_response = nil
    @start_codex_authorization_response = nil
    @codex_authorization_status_sequence = []
    @poll_codex_authorization_sequence = []
    @revoke_codex_authorization_response = { "authorization" => { "status" => "missing" } }
    @create_ingress_binding_responses = {}
    @update_ingress_binding_responses = {}
    @weixin_start_login_response = nil
    @weixin_login_status_sequence = []
  end

  def stored_base_url
    config_store.read["base_url"]
  end

  def session_token
    credential_store.read["session_token"]
  end

  def persist_base_url(base_url)
    calls << [:persist_base_url, base_url]
    config_store.merge("base_url" => base_url)
  end

  def persist_session_token(session_token)
    calls << [:persist_session_token, session_token]
    credential_store.write("session_token" => session_token)
  end

  def clear_session_token
    calls << [:clear_session_token]
    credential_store.clear
  end

  def persist_operator_email(email)
    calls << [:persist_operator_email, email]
    config_store.merge("operator_email" => email)
  end

  def persist_workspace_context(workspace_id: nil, workspace_agent_id: nil)
    calls << [:persist_workspace_context, workspace_id, workspace_agent_id]
    current_payload = config_store.read
    next_payload = current_payload.dup

    workspace_changed =
      workspace_id && workspace_id != current_payload["workspace_id"]
    workspace_agent_changed =
      workspace_agent_id && workspace_agent_id != current_payload["workspace_agent_id"]

    if workspace_changed
      next_payload["workspace_id"] = workspace_id
      next_payload.delete("workspace_agent_id")
      next_payload.delete("telegram_ingress_binding_id")
      next_payload.delete("telegram_webhook_ingress_binding_id")
      next_payload.delete("weixin_ingress_binding_id")
    elsif workspace_id
      next_payload["workspace_id"] = workspace_id
    end

    if workspace_agent_changed
      next_payload["workspace_agent_id"] = workspace_agent_id
      next_payload.delete("telegram_ingress_binding_id")
      next_payload.delete("telegram_webhook_ingress_binding_id")
      next_payload.delete("weixin_ingress_binding_id")
    elsif workspace_agent_id
      next_payload["workspace_agent_id"] = workspace_agent_id
    end

    config_store.write(next_payload) if next_payload != current_payload
  end

  def stored_ingress_binding_id(platform)
    config_store.read["#{platform}_ingress_binding_id"]
  end

  def persist_ingress_binding_id(platform, ingress_binding_id)
    calls << [:persist_ingress_binding_id, platform, ingress_binding_id]
    config_store.merge("#{platform}_ingress_binding_id" => ingress_binding_id)
  end

  def bootstrap_status
    calls << [:bootstrap_status]
    @bootstrap_status_payload
  end

  def bootstrap(attributes)
    calls << [:bootstrap, attributes]
    @bootstrap_response || raise("missing bootstrap_response")
  end

  def login(email:, password:)
    calls << [:login, email, password]
    @login_response || raise("missing login_response")
  end

  def current_session
    calls << [:current_session]
    @session_response || raise("missing session_response")
  end

  def logout
    calls << [:logout]
    credential_store.clear
    @logout_response
  end

  def readiness_snapshot
    calls << [:readiness_snapshot]
    @readiness_payload
  end

  def list_workspaces
    calls << [:list_workspaces]
    @workspaces_response
  end

  def create_workspace(name:, privacy:, is_default:)
    calls << [:create_workspace, name, privacy, is_default]
    @create_workspace_response || raise("missing create_workspace_response")
  end

  def list_agents
    calls << [:list_agents]
    @agents_response
  end

  def attach_workspace_agent(workspace_id:, agent_id:)
    calls << [:attach_workspace_agent, workspace_id, agent_id]
    @attach_workspace_agent_response || raise("missing attach_workspace_agent_response")
  end

  def start_codex_authorization
    calls << [:start_codex_authorization]
    @start_codex_authorization_response || raise("missing start_codex_authorization_response")
  end

  def codex_authorization_status
    calls << [:codex_authorization_status]
    @codex_authorization_status_sequence.shift || raise("missing codex_authorization_status_sequence")
  end

  def poll_codex_authorization
    calls << [:poll_codex_authorization]
    @poll_codex_authorization_sequence.shift || raise("missing poll_codex_authorization_sequence")
  end

  def revoke_codex_authorization
    calls << [:revoke_codex_authorization]
    @revoke_codex_authorization_response
  end

  def create_ingress_binding(workspace_agent_id:, platform:)
    calls << [:create_ingress_binding, workspace_agent_id, platform]
    @create_ingress_binding_responses.fetch(platform) do
      raise("missing create_ingress_binding_response for #{platform}")
    end
  end

  def update_ingress_binding(workspace_agent_id:, ingress_binding_id:, channel_connector:, reissue_setup_secret: false)
    calls << [:update_ingress_binding, workspace_agent_id, ingress_binding_id, channel_connector, reissue_setup_secret]
    @update_ingress_binding_responses.fetch(ingress_binding_id) do
      raise("missing update_ingress_binding_response for #{ingress_binding_id}")
    end
  end

  def start_weixin_login(workspace_agent_id:, ingress_binding_id:)
    calls << [:start_weixin_login, workspace_agent_id, ingress_binding_id]
    @weixin_start_login_response || raise("missing weixin_start_login_response")
  end

  def weixin_login_status(workspace_agent_id:, ingress_binding_id:)
    calls << [:weixin_login_status, workspace_agent_id, ingress_binding_id]
    @weixin_login_status_sequence.shift || raise("missing weixin_login_status_sequence")
  end
end

FakeShellResult = Struct.new(:success?, :stdout, :stderr, keyword_init: true)

class FakeBrowserLauncher
  attr_reader :opened_urls

  def initialize
    @opened_urls = []
  end

  def open(url)
    @opened_urls << url
    true
  end
end

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
