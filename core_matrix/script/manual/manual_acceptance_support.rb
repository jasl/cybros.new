ENV["RAILS_ENV"] ||= "development"

require "action_controller"
require "fileutils"
require "json"
require "net/http"
require "open3"
require "pathname"
require "stringio"
require "uri"
require "timeout"
require_relative "../../config/environment"

module ManualAcceptanceSupport
  module_function

  CONTROL_BASE_URL = ENV.fetch("CORE_MATRIX_BASE_URL", "http://127.0.0.1:3000")

  RESET_MODELS = [
    PublicationAccessEvent,
    Publication,
    ExecutionLease,
    ToolInvocation,
    ToolBinding,
    ToolImplementation,
    ToolDefinition,
    ImplementationSource,
    SubagentSession,
    ProcessRun,
    WorkflowArtifact,
    WorkflowNodeEvent,
    WorkflowEdge,
    WorkflowNode,
    HumanInteractionRequest,
    WorkflowRun,
    ConversationEvent,
    ConversationImport,
    ConversationSummarySegment,
    ConversationMessageVisibility,
    MessageAttachment,
    Message,
    Turn,
    ConversationClosure,
    Conversation,
    CanonicalVariable,
    CapabilitySnapshot,
    AgentDeployment,
    AgentEnrollment,
    ExecutionEnvironment,
    AgentInstallation,
    Workspace,
    UserAgentBinding,
    ProviderEntitlement,
    ProviderPolicy,
    ProviderCredential,
    UsageRollup,
    UsageEvent,
    ExecutionProfileFact,
    AuditLog,
    Session,
    Invitation,
    User,
    Identity,
    Installation,
  ].freeze

  def reset_backend_state!
    ApplicationRecord.with_connection do |conn|
      conn.disable_referential_integrity do
        RESET_MODELS.each(&:delete_all)
      end
    end
  end

  def bootstrap_and_seed!(bundled_agent_configuration: { enabled: false })
    bootstrap = Installations::BootstrapFirstAdmin.call(
      name: "Primary Installation",
      email: "admin@example.com",
      password: "Password123!",
      password_confirmation: "Password123!",
      display_name: "Primary Admin",
      bundled_agent_configuration: bundled_agent_configuration
    )

    silence_stdout do
      load Rails.root.join("db", "seeds.rb")
    end
    bootstrap
  end

  def token_headers(machine_credential)
    {
      "Authorization" => ActionController::HttpAuthentication::Token.encode_credentials(machine_credential),
    }
  end

  def http_get_json(url, headers: {})
    uri = URI(url)
    request = Net::HTTP::Get.new(uri)
    headers.each { |key, value| request[key] = value }
    execute_http(uri, request)
  end

  def http_post_json(url, payload, headers: {})
    uri = URI(url)
    request = Net::HTTP::Post.new(uri)
    request["Content-Type"] = "application/json"
    headers.each { |key, value| request[key] = value }
    request.body = JSON.generate(payload)
    execute_http(uri, request)
  end

  def execute_http(uri, request)
    response = Net::HTTP.start(uri.host, uri.port) do |http|
      http.request(request)
    end
    body = response.body.to_s
    parsed = body.empty? ? {} : JSON.parse(body)
    raise "HTTP #{response.code}: #{body}" unless response.code.to_i.between?(200, 299)

    parsed
  end

  def live_manifest(base_url:)
    http_get_json("#{base_url}/runtime/manifest")
  end

  def run_fenix_mailbox_pump_once!(machine_credential:, limit: 10, inline: true)
    run_fenix_runtime_task!(
      task_name: "runtime:mailbox_pump_once",
      machine_credential:,
      env: {
        "LIMIT" => limit.to_s,
        "INLINE" => inline ? "true" : "false",
      }
    )
  end

  def run_fenix_control_loop_once!(machine_credential:, limit: 10, inline: true, realtime_timeout_seconds: 5)
    run_fenix_runtime_task!(
      task_name: "runtime:control_loop_once",
      machine_credential:,
      env: {
        "LIMIT" => limit.to_s,
        "INLINE" => inline ? "true" : "false",
        "REALTIME_TIMEOUT_SECONDS" => realtime_timeout_seconds.to_s,
      }
    )
  end

  def run_fenix_runtime_task!(task_name:, machine_credential:, env:)
    project_root = fenix_project_root
    task_env = {
      "CORE_MATRIX_BASE_URL" => CONTROL_BASE_URL,
      "CORE_MATRIX_MACHINE_CREDENTIAL" => machine_credential,
      "BUNDLE_GEMFILE" => project_root.join("Gemfile").to_s,
    }.merge(env)

    stdout = nil
    stderr = nil
    status = nil

    Bundler.with_unbundled_env do
      stdout, stderr, status = Open3.capture3(
        task_env,
        "bin/rails",
        task_name,
        chdir: project_root.to_s
      )
    end

    raise "fenix mailbox pump failed: #{stderr.presence || stdout}" unless status.success?

    JSON.parse(stdout)
  end

  def with_fenix_control_worker!(machine_credential:, limit: 10, inline: true, realtime_timeout_seconds: 5)
    project_root = fenix_project_root
    task_env = {
      "CORE_MATRIX_BASE_URL" => CONTROL_BASE_URL,
      "CORE_MATRIX_MACHINE_CREDENTIAL" => machine_credential,
      "BUNDLE_GEMFILE" => project_root.join("Gemfile").to_s,
      "LIMIT" => limit.to_s,
      "INLINE" => inline ? "true" : "false",
      "REALTIME_TIMEOUT_SECONDS" => realtime_timeout_seconds.to_s,
    }

    reader, writer = IO.pipe
    pid = nil

    Bundler.with_unbundled_env do
      pid = Process.spawn(
        task_env,
        "bin/rails",
        "runtime:control_loop_forever",
        chdir: project_root.to_s,
        out: writer,
        err: writer
      )
    end

    writer.close
    wait_for_worker_ready!(reader: reader, pid: pid)
    yield pid
  ensure
    reader&.close unless reader.nil? || reader.closed?
    stop_fenix_control_worker!(pid) if pid.present?
  end

  def fenix_project_root
    Pathname.new(ENV.fetch("FENIX_PROJECT_ROOT", Rails.root.join("..", "agents", "fenix").to_s))
  end

  def wait_for_agent_task_terminal!(agent_task_run:, timeout_seconds: 10, poll_interval_seconds: 0.1)
    deadline_at = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout_seconds

    loop do
      reloaded = agent_task_run.reload
      return reloaded if %w[completed failed interrupted canceled].include?(reloaded.lifecycle_state)

      if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline_at
        raise "timed out waiting for agent task run #{agent_task_run.public_id} to finish"
      end

      sleep(poll_interval_seconds)
    end
  end

  def wait_for_process_run!(workflow_node:, timeout_seconds: 10, poll_interval_seconds: 0.1)
    deadline_at = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout_seconds

    loop do
      process_run = ProcessRun.find_by(workflow_node: workflow_node)
      return process_run if process_run.present?

      if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline_at
        raise "timed out waiting for process run for workflow node #{workflow_node.public_id}"
      end

      sleep(poll_interval_seconds)
    end
  end

  def wait_for_workflow_run_terminal!(workflow_run:, timeout_seconds: 15, poll_interval_seconds: 0.1)
    deadline_at = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout_seconds

    loop do
      reloaded = workflow_run.reload
      return reloaded if %w[completed failed canceled].include?(reloaded.lifecycle_state)

      if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline_at
        raise "timed out waiting for workflow run #{reloaded.public_id} to finish"
      end

      sleep(poll_interval_seconds)
    end
  end

  def wait_for_process_run_state!(process_run:, lifecycle_states:, close_states: nil, timeout_seconds: 10, poll_interval_seconds: 0.1)
    deadline_at = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout_seconds
    lifecycle_states = Array(lifecycle_states)
    close_states = Array(close_states).compact if close_states.present?

    loop do
      reloaded = process_run.reload
      lifecycle_match = lifecycle_states.include?(reloaded.lifecycle_state)
      close_match = close_states.blank? || close_states.include?(reloaded.close_state)
      return reloaded if lifecycle_match && close_match

      if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline_at
        raise "timed out waiting for process run #{reloaded.public_id} to reach #{lifecycle_states.join(", ")}"
      end

      sleep(poll_interval_seconds)
    end
  end

  def report_results_for(agent_task_run:)
    AgentControlReportReceipt
      .where(agent_task_run:)
      .order(:created_at, :id)
      .pluck(:result_code)
  end

  def create_external_agent_installation!(installation:, actor:, key:, display_name:)
    agent_installation = AgentInstallation.create!(
      installation: installation,
      key: key,
      display_name: display_name,
      visibility: "global",
      lifecycle_state: "active"
    )
    enrollment = AgentEnrollments::Issue.call(
      agent_installation: agent_installation,
      actor: actor,
      expires_at: 2.hours.from_now
    )

    {
      agent_installation: agent_installation,
      enrollment_token: enrollment.plaintext_token,
    }
  end

  def register_external_runtime!(
    enrollment_token:,
    runtime_base_url:,
    environment_fingerprint:,
    fingerprint:
  )
    manifest = live_manifest(base_url: runtime_base_url)
    registration = http_post_json(
      "#{CONTROL_BASE_URL}/agent_api/registrations",
      {
        enrollment_token: enrollment_token,
        environment_fingerprint: environment_fingerprint,
        environment_kind: "local",
        environment_connection_metadata: manifest.fetch("environment_connection_metadata", {
          "transport" => "http",
          "base_url" => runtime_base_url,
        }),
        fingerprint: fingerprint,
        endpoint_metadata: manifest.fetch("endpoint_metadata"),
        protocol_version: manifest.fetch("protocol_version"),
        sdk_version: manifest.fetch("sdk_version"),
        environment_capability_payload: manifest.fetch("environment_capability_payload", {}),
        environment_tool_catalog: manifest.fetch("environment_tool_catalog", []),
        protocol_methods: manifest.fetch("protocol_methods"),
        tool_catalog: manifest.fetch("tool_catalog"),
        profile_catalog: manifest.fetch("profile_catalog"),
        config_schema_snapshot: manifest.fetch("config_schema_snapshot"),
        conversation_override_schema_snapshot: manifest.fetch("conversation_override_schema_snapshot"),
        default_config_snapshot: manifest.fetch("default_config_snapshot"),
      }
    )
    machine_credential = registration.fetch("machine_credential")
    heartbeat = http_post_json(
      "#{CONTROL_BASE_URL}/agent_api/heartbeats",
      {
        health_status: "healthy",
        health_metadata: { "release" => manifest.fetch("sdk_version") },
        auto_resume_eligible: true,
      },
      headers: token_headers(machine_credential)
    )
    deployment = AgentDeployment.find_by_public_id!(registration.fetch("deployment_id"))

    {
      manifest: manifest,
      registration: registration,
      heartbeat: heartbeat,
      machine_credential: machine_credential,
      deployment: deployment,
    }
  end

  def register_bundled_runtime_from_manifest!(
    installation:,
    runtime_base_url:,
    environment_fingerprint:,
    fingerprint:,
    sdk_version:
  )
    manifest = live_manifest(base_url: runtime_base_url)
    runtime = Installations::RegisterBundledAgentRuntime.call(
      installation: installation,
      configuration: {
        enabled: true,
        agent_key: "fenix",
        display_name: "Bundled Fenix",
        visibility: "global",
        lifecycle_state: "active",
        environment_kind: "local",
        environment_fingerprint: environment_fingerprint,
        connection_metadata: {
          "transport" => "http",
          "base_url" => runtime_base_url,
        },
        endpoint_metadata: manifest.fetch("endpoint_metadata"),
        environment_capability_payload: manifest.fetch("environment_capability_payload", {}),
        environment_tool_catalog: manifest.fetch("environment_tool_catalog", []),
        fingerprint: fingerprint,
        protocol_version: manifest.fetch("protocol_version"),
        sdk_version: sdk_version,
        protocol_methods: manifest.fetch("protocol_methods"),
        tool_catalog: manifest.fetch("tool_catalog"),
        profile_catalog: manifest.fetch("profile_catalog"),
        config_schema_snapshot: manifest.fetch("config_schema_snapshot"),
        conversation_override_schema_snapshot: manifest.fetch("conversation_override_schema_snapshot"),
        default_config_snapshot: manifest.fetch("default_config_snapshot"),
      }
    )

    {
      manifest: manifest,
      runtime: runtime,
      machine_credential: bundled_machine_credential(fingerprint),
    }
  end

  def bundled_machine_credential(fingerprint)
    "bundled-runtime:#{fingerprint}"
  end

  def enable_default_workspace!(deployment:)
    user = User.find_by!(installation: deployment.installation, role: "admin")
    user_binding = UserAgentBindings::Enable.call(
      user: user,
      agent_installation: deployment.agent_installation
    ).binding

    user_binding.workspaces.find_by!(is_default: true)
  end

  def create_conversation!(deployment:)
    workspace = enable_default_workspace!(deployment: deployment)

    {
      workspace: workspace,
      conversation: Conversations::CreateRoot.call(
        workspace: workspace,
        execution_environment: deployment.execution_environment,
        agent_deployment: deployment
      ),
    }
  end

  def start_turn_workflow_on_conversation!(
    conversation:,
    deployment:,
    content:,
    root_node_key:,
    root_node_type:,
    decision_source:,
    selector_source: "conversation",
    selector: "candidate:dev/mock-model",
    initial_kind: nil,
    initial_payload: {}
  )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: content,
      agent_deployment: deployment,
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    workflow_run = Workflows::CreateForTurn.call(
      turn: turn,
      root_node_key: root_node_key,
      root_node_type: root_node_type,
      decision_source: decision_source,
      metadata: {},
      selector_source: selector_source,
      selector: selector,
      initial_kind: initial_kind,
      initial_payload: initial_payload
    )

    {
      turn: turn.reload,
      workflow_run: workflow_run.reload,
      agent_task_run: initial_kind.present? ? AgentTaskRun.find_by!(workflow_run: workflow_run).reload : nil,
    }
  end

  def execute_provider_workflow!(workflow_run:, timeout_seconds: 3600)
    dispatched_node = Workflows::ExecuteRun.call(
      workflow_run: workflow_run,
      messages: workflow_run.execution_snapshot.conversation_projection.fetch("messages").map { |entry| entry.slice("role", "content") }
    )
    execute_inline_if_queued!(workflow_node: dispatched_node) if dispatched_node.present?
    wait_for_workflow_run_terminal!(workflow_run:, timeout_seconds:)
  end

  def execute_provider_turn_on_conversation!(conversation:, deployment:, content:)
    run = start_turn_workflow_on_conversation!(
      conversation: conversation,
      deployment: deployment,
      content: content,
      root_node_key: "turn_step",
      root_node_type: "turn_step",
      decision_source: "system"
    )
    execute_provider_workflow!(workflow_run: run.fetch(:workflow_run))
    run.transform_values { |value| value.respond_to?(:reload) ? value.reload : value }
  end

  def run_fenix_mailbox_task!(
    deployment:,
    machine_credential:,
    runtime_base_url: nil,
    content:,
    mode:,
    extra_payload: {},
    delivery_mode: "realtime"
  )
    _unused_runtime_base_url = runtime_base_url
    conversation_context = create_conversation!(deployment: deployment)
    run = start_turn_workflow_on_conversation!(
      conversation: conversation_context.fetch(:conversation),
      deployment: deployment,
      content: content,
      root_node_key: "agent_turn_step",
      root_node_type: "turn_step",
      decision_source: "agent_program",
      initial_kind: "turn_step",
      initial_payload: { "mode" => mode }.merge(extra_payload)
    )
    pump_result =
      if delivery_mode == "realtime"
        run_fenix_control_loop_once!(machine_credential:)
      else
        run_fenix_mailbox_pump_once!(machine_credential:)
      end
    agent_task_run = wait_for_agent_task_terminal!(agent_task_run: run.fetch(:agent_task_run))
    mailbox_item = agent_task_run.agent_control_mailbox_items.order(:created_at, :id).last
    raise "expected mailbox item for task run #{agent_task_run.public_id}" if mailbox_item.blank?

    execution = pump_result.fetch("items").find do |item|
      item["kind"] == "runtime_execution" && item["mailbox_item_id"] == mailbox_item.public_id
    end
    raise "expected runtime execution summary for mailbox item #{mailbox_item.public_id}" if execution.blank?

    run.merge(
      conversation: conversation_context.fetch(:conversation).reload,
      mailbox_item: mailbox_item,
      execution: execution,
      report_results: report_results_for(agent_task_run:)
    )
  end

  def workflow_node_keys(workflow_run)
    workflow_run.workflow_nodes.order(:ordinal).pluck(:node_key)
  end

  def workflow_edge_keys(workflow_run)
    workflow_run.workflow_edges
      .includes(:from_node, :to_node)
      .sort_by { |edge| [edge.from_node.ordinal, edge.to_node.ordinal] }
      .map { |edge| "#{edge.from_node.node_key}->#{edge.to_node.node_key}" }
  end

  def workflow_state_hash(conversation:, workflow_run:, turn:, agent_task_run: nil, extra: {})
    {
      "conversation_state" => conversation.reload.lifecycle_state,
      "workflow_lifecycle_state" => workflow_run.reload.lifecycle_state,
      "workflow_wait_state" => workflow_run.wait_state,
      "turn_lifecycle_state" => turn.reload.lifecycle_state,
    }.tap do |state|
      if agent_task_run.present?
        state["agent_task_run_state"] = agent_task_run.reload.lifecycle_state
        state["selected_output_message_id"] = turn.selected_output_message&.public_id
        state["selected_output_content"] = turn.selected_output_message&.content
      end
      extra.each { |key, value| state[key] = value }
    end
  end

  def scenario_result(scenario:, expected_dag_shape:, observed_dag_shape:, expected_conversation_state:, observed_conversation_state:, proof_artifact_path: nil, extra: {})
    {
      "scenario" => scenario,
      "passed" => expected_dag_shape == observed_dag_shape &&
        expected_conversation_state.all? { |key, value| observed_conversation_state[key] == value },
      "proof_artifact_path" => proof_artifact_path,
      "expected_dag_shape" => expected_dag_shape,
      "observed_dag_shape" => observed_dag_shape,
      "expected_conversation_state" => expected_conversation_state,
      "observed_conversation_state" => observed_conversation_state,
    }.merge(extra)
  end

  def write_json(payload, io: $stdout)
    io.puts JSON.pretty_generate(payload)
  end

  def silence_stdout
    original_stdout = $stdout
    $stdout = StringIO.new
    yield
  ensure
    $stdout = original_stdout
  end

  def wait_for_worker_ready!(reader:, pid:, timeout_seconds: 15)
    Timeout.timeout(timeout_seconds) do
      loop do
        line = reader.gets
        raise "fenix control worker exited before becoming ready" if line.nil? && !process_alive?(pid)
        next if line.blank?

        payload = JSON.parse(line)
        return payload if payload["event"] == "ready"
      rescue JSON::ParserError
        next
      end
    end
  rescue Timeout::Error
    raise "timed out waiting for fenix control worker to become ready"
  end

  def stop_fenix_control_worker!(pid)
    return if pid.blank?

    Process.kill("TERM", pid)

    Timeout.timeout(5) do
      Process.wait(pid)
    end
  rescue Errno::ESRCH, Errno::ECHILD
    nil
  rescue Timeout::Error
    Process.kill("KILL", pid)
    Process.wait(pid)
  rescue Errno::ESRCH, Errno::ECHILD
    nil
  end

  def process_alive?(pid)
    Process.kill(0, pid)
    true
  rescue Errno::ESRCH
    false
  end

  def execute_inline_if_queued!(workflow_node:)
    current_node = WorkflowNode.find_by(public_id: workflow_node.public_id)
    return if current_node.blank?
    return unless current_node.queued? || current_node.pending?

    Workflows::ExecuteNode.call(
      workflow_node: current_node,
      messages: current_node.workflow_run.execution_snapshot.conversation_projection.fetch("messages").map { |entry| entry.slice("role", "content") }
    )
  end
end
