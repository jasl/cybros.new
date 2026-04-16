require "bundler/setup"
require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "json"
require "stringio"

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "core_matrix_cli"

class TestInput < StringIO
  def noecho
    yield self
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
    CoreMatrixCLI.runtime_factory = -> { runtime }
    yield
  ensure
    CoreMatrixCLI.runtime_factory = previous_runtime_factory
  end

  def run_cli(*args, input: "", runtime:)
    output = nil
    stdin = $stdin
    $stdin = TestInput.new(input)

    with_runtime_factory(runtime) do
      stdout, stderr = capture_io do
        CoreMatrixCLI::CLI.start(args.flatten.map(&:to_s))
      end
      output = stdout + stderr
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
    :create_workspace_response, :agents_response, :attach_workspace_agent_response

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
    payload = {}
    payload["workspace_id"] = workspace_id if workspace_id
    payload["workspace_agent_id"] = workspace_agent_id if workspace_agent_id
    config_store.merge(payload) if payload.any?
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
