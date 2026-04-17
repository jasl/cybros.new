class FakeCoreMatrixAPI
  attr_reader :calls
  attr_accessor :bootstrap_status_payload, :bootstrap_response, :login_response,
    :session_response, :logout_response, :installation_response, :workspaces_response,
    :create_workspace_response, :agents_response, :attach_workspace_agent_response,
    :provider_status_responses, :start_codex_authorization_response,
    :codex_authorization_status_sequence, :poll_codex_authorization_sequence,
    :revoke_codex_authorization_response, :create_ingress_binding_responses,
    :update_ingress_binding_responses, :show_ingress_binding_responses,
    :weixin_start_login_response, :weixin_login_status_sequence

  def initialize
    @calls = []
    @bootstrap_status_payload = { "bootstrap_state" => "bootstrapped" }
    @bootstrap_response = nil
    @login_response = nil
    @session_response = nil
    @logout_response = {}
    @installation_response = {}
    @workspaces_response = { "workspaces" => [] }
    @create_workspace_response = nil
    @agents_response = { "agents" => [] }
    @attach_workspace_agent_response = nil
    @provider_status_responses = {}
    @start_codex_authorization_response = nil
    @codex_authorization_status_sequence = []
    @poll_codex_authorization_sequence = []
    @revoke_codex_authorization_response = { "authorization" => { "status" => "missing" } }
    @create_ingress_binding_responses = {}
    @update_ingress_binding_responses = {}
    @show_ingress_binding_responses = {}
    @weixin_start_login_response = nil
    @weixin_login_status_sequence = []
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
    @logout_response
  end

  def installation_status
    calls << [:installation_status]
    @installation_response
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

  def provider_status(provider_handle)
    calls << [:provider_status, provider_handle]
    provider_status_responses.fetch(provider_handle) { raise("missing provider_status for #{provider_handle}") }
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
    @create_ingress_binding_responses.fetch(platform) { raise("missing create_ingress_binding response for #{platform}") }
  end

  def update_ingress_binding(workspace_agent_id:, ingress_binding_id:, channel_connector:, reissue_setup_secret: false)
    calls << [:update_ingress_binding, workspace_agent_id, ingress_binding_id, channel_connector, reissue_setup_secret]
    @update_ingress_binding_responses.fetch(ingress_binding_id) { raise("missing update_ingress_binding response for #{ingress_binding_id}") }
  end

  def show_ingress_binding(workspace_agent_id:, ingress_binding_id:)
    calls << [:show_ingress_binding, workspace_agent_id, ingress_binding_id]
    @show_ingress_binding_responses.fetch(ingress_binding_id) { raise("missing show_ingress_binding response for #{ingress_binding_id}") }
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
