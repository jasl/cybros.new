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

  def initialize(test_case:, agent_definition_version:, agent_connection_credential:, execution_runtime_connection_credential: nil, execution_runtime_connection: nil)
    @test_case = test_case
    @agent_definition_version = agent_definition_version
    @agent_connection_credential = agent_connection_credential
    @execution_runtime_connection_credential = execution_runtime_connection_credential
    @execution_runtime_connection = execution_runtime_connection
  end

  attr_reader :agent_definition_version

  def connect_websocket!
    AgentControl::RealtimeLinks::Open.call(agent_definition_version: agent_definition_version)
    return if resolved_execution_runtime_connection.blank?

    AgentControl::RealtimeLinks::Open.call(execution_runtime_connection: resolved_execution_runtime_connection)
  end

  def disconnect_websocket!
    AgentControl::RealtimeLinks::Close.call(agent_definition_version: agent_definition_version)
    return if resolved_execution_runtime_connection.blank?

    AgentControl::RealtimeLinks::Close.call(execution_runtime_connection: resolved_execution_runtime_connection)
  end

  def stream_names
    names = [AgentControl::StreamName.for_delivery_endpoint(agent_definition_version)]
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
    agent_response = post_and_parse(
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
        agent_response.fetch("mailbox_items", []),
        execution_response&.fetch("mailbox_items", []) || []
      ),
    }
  end

  def report!(method_id:, **params)
    if execution_runtime_report?(method_id:, params:)
      event_payload = params.merge(method_id: method_id)

      if execution_runtime_connection_credential.present?
        response = post_and_parse(
          "/execution_runtime_api/events/batch",
          params: { events: [event_payload] },
          headers: @test_case.send(:execution_runtime_api_headers, execution_runtime_connection_credential)
        )

        return normalize_event_batch_response(response)
      end

      raise ArgumentError, "execution_runtime_connection_credential is required for #{method_id}" if resolved_execution_runtime_connection.blank?

      result = AgentControl::ApplyEventBatch.call(
        execution_runtime_connection: resolved_execution_runtime_connection,
        events: [event_payload]
      )

      return normalize_event_batch_response(result.merge("http_status" => 200))
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
    @execution_runtime_connection || agent_definition_version.agent.default_execution_runtime&.active_execution_runtime_connection
  end

  def poll_execution!(limit:)
    post_and_parse(
      "/execution_runtime_api/mailbox/pull",
      params: { limit: limit },
      headers: @test_case.send(:execution_runtime_api_headers, execution_runtime_connection_credential)
    )
  end

  def merge_mailbox_items(agent_items, execution_items)
    (agent_items + execution_items).sort_by do |mailbox_item|
      [
        mailbox_item.fetch("priority", 0),
        mailbox_item.fetch("available_at", ""),
        mailbox_item.fetch("item_id"),
      ]
    end
  end

  def execution_runtime_report?(method_id:, params:)
    EXECUTION_REPORT_METHODS.include?(method_id) ||
      runtime_close_report?(method_id:, params:)
  end

  def runtime_close_report?(method_id:, params:)
    CLOSE_REPORT_METHODS.include?(method_id) &&
      (params[:resource_type] || params["resource_type"]).to_s == "ProcessRun"
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
      installation_id: agent_definition_version.installation_id,
      resource_type: resource_type,
      public_id: resource_id
    )
  end

  def normalize_mailbox_item(payload)
    payload.is_a?(String) ? JSON.parse(payload) : payload
  end

  def normalize_event_batch_response(response)
    first_result = response.fetch("results").fetch(0)
    result_code = first_result.fetch("result")

    {
      "result" => result_code,
      "error" => first_result["error"],
      "mailbox_items" => first_result.fetch("mailbox_items", []),
      "http_status" => normalized_http_status(response.fetch("http_status", 200), result_code),
    }
  end

  def normalized_http_status(response_status, result_code)
    response_status.to_i == 200 ? batch_http_status_for(result_code) : response_status
  end

  def batch_http_status_for(result_code)
    case result_code
    when "stale"
      409
    when "not_found"
      404
    when "invalid"
      422
    else
      200
    end
  end
end
