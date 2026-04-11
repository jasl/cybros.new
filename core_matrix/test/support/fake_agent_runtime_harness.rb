class FakeAgentRuntimeHarness
  EXECUTION_REPORT_METHODS = %w[
    execution_started
    execution_progress
    execution_complete
    execution_fail
    execution_interrupted
    process_started
    process_output
    process_exited
  ].freeze
  CLOSE_REPORT_METHODS = %w[
    resource_close_acknowledged
    resource_closed
    resource_close_failed
  ].freeze

  def initialize(test_case:, agent_snapshot:, agent_connection_credential:, execution_runtime_connection_credential: nil, execution_runtime_connection: nil)
    @test_case = test_case
    @agent_snapshot = agent_snapshot
    @agent_connection_credential = agent_connection_credential
    @execution_runtime_connection_credential = execution_runtime_connection_credential
    @execution_runtime_connection = execution_runtime_connection
  end

  attr_reader :agent_snapshot

  def connect_websocket!
    AgentControl::RealtimeLinks::Open.call(agent_snapshot: agent_snapshot)
    return if resolved_execution_runtime_connection.blank?

    AgentControl::RealtimeLinks::Open.call(execution_runtime_connection: resolved_execution_runtime_connection)
  end

  def disconnect_websocket!
    AgentControl::RealtimeLinks::Close.call(agent_snapshot: agent_snapshot)
    return if resolved_execution_runtime_connection.blank?

    AgentControl::RealtimeLinks::Close.call(execution_runtime_connection: resolved_execution_runtime_connection)
  end

  def stream_names
    names = [AgentControl::StreamName.for_delivery_endpoint(agent_snapshot)]
    if resolved_execution_runtime_connection.present?
      names << AgentControl::StreamName.for_execution_runtime_connection(resolved_execution_runtime_connection)
    end
    names
  end

  def websocket_mailbox_items
    stream_names.flat_map { |stream_name| @test_case.broadcasts(stream_name) }.map do |payload|
      normalize_mailbox_item(payload)
    end
  end

  def capture_websocket_mailbox_items(&block)
    existing_counts = stream_names.to_h { |stream_name| [stream_name, @test_case.broadcasts(stream_name).length] }
    block.call
    stream_names.flat_map do |stream_name|
      @test_case.broadcasts(stream_name).drop(existing_counts.fetch(stream_name, 0))
    end.map do |payload|
      normalize_mailbox_item(payload)
    end
  end

  def poll!(limit: 10)
    program_response = post_and_parse(
      "/agent_api/control/poll",
      params: { limit: limit },
      headers: @test_case.send(:agent_api_headers, @agent_connection_credential)
    )
    execution_response =
      if execution_runtime_connection_credential.present?
        poll_execution!(limit: limit)
      elsif resolved_execution_runtime_connection.present?
        {
          "mailbox_items" => AgentControl::SerializeMailboxItems.call(
            AgentControl::Poll.call(execution_runtime_connection: resolved_execution_runtime_connection, limit: limit)
          ),
        }
      end

    {
      "mailbox_items" => merge_mailbox_items(
        program_response.fetch("mailbox_items", []),
        execution_response&.fetch("mailbox_items", []) || []
      ),
    }
  end

  def report!(method_id:, **params)
    if execution_report?(method_id:, params:)
      if execution_runtime_connection_credential.present?
        return post_and_parse(
          "/execution_runtime_api/control/report",
          params: params.merge(method_id: method_id),
          headers: @test_case.send(:execution_runtime_api_headers, execution_runtime_connection_credential)
        )
      end

      raise ArgumentError, "execution_runtime_connection_credential is required for #{method_id}" if resolved_execution_runtime_connection.blank?

      result = AgentControl::Report.call(
        agent_snapshot: agent_snapshot,
        execution_runtime_connection: resolved_execution_runtime_connection,
        resource: resolved_execution_resource_for(params),
        payload: params.merge(method_id: method_id)
      )

      return {
        "result" => result.code,
        "mailbox_items" => AgentControl::SerializeMailboxItems.call(result.mailbox_items),
        "http_status" => Rack::Utils.status_code(result.http_status),
      }
    end

    post_and_parse(
      "/agent_api/control/report",
      params: params.merge(method_id: method_id),
      headers: @test_case.send(:agent_api_headers, @agent_connection_credential)
    )
  end

  private

  attr_reader :execution_runtime_connection_credential

  def resolved_execution_runtime_connection
    @execution_runtime_connection || agent_snapshot.agent.default_execution_runtime&.active_execution_runtime_connection
  end

  def poll_execution!(limit:)
    post_and_parse(
      "/execution_runtime_api/control/poll",
      params: { limit: limit },
      headers: @test_case.send(:execution_runtime_api_headers, execution_runtime_connection_credential)
    )
  end

  def merge_mailbox_items(program_items, execution_items)
    (program_items + execution_items).sort_by do |mailbox_item|
      [
        mailbox_item.fetch("priority", 0),
        mailbox_item.fetch("available_at", ""),
        mailbox_item.fetch("item_id"),
      ]
    end
  end

  def execution_report?(method_id:, params:)
    EXECUTION_REPORT_METHODS.include?(method_id) ||
      (CLOSE_REPORT_METHODS.include?(method_id) && params[:resource_type].to_s == "ProcessRun")
  end

  def post_and_parse(path, params:, headers:)
    @test_case.post(
      path,
      params: params,
      headers: headers,
      as: :json
    )

    parse_response.merge("http_status" => @test_case.response.status)
  end

  def parse_response
    body = @test_case.response.body
    body.present? ? JSON.parse(body) : {}
  end

  def resolved_execution_resource_for(params)
    resource_type = params[:resource_type] || params["resource_type"]
    resource_id = params[:resource_id] || params["resource_id"]
    return nil if resource_type.blank? || resource_id.blank?

    AgentControl::ClosableResourceRegistry.find!(
      installation_id: agent_snapshot.installation_id,
      resource_type: resource_type,
      public_id: resource_id
    )
  end

  def normalize_mailbox_item(payload)
    payload.is_a?(String) ? JSON.parse(payload) : payload
  end
end
