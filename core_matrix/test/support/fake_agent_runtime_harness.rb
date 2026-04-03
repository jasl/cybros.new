class FakeAgentRuntimeHarness
  EXECUTION_REPORT_METHODS = %w[
    process_started
    process_output
    process_exited
  ].freeze
  CLOSE_REPORT_METHODS = %w[
    resource_close_acknowledged
    resource_closed
    resource_close_failed
  ].freeze

  def initialize(test_case:, deployment:, machine_credential:, execution_machine_credential: nil)
    @test_case = test_case
    @deployment = deployment
    @machine_credential = machine_credential
    @execution_machine_credential = execution_machine_credential
  end

  attr_reader :deployment

  def connect_websocket!
    AgentControl::RealtimeLinks::Open.call(deployment: deployment)
  end

  def disconnect_websocket!
    AgentControl::RealtimeLinks::Close.call(deployment: deployment)
  end

  def stream_name
    AgentControl::StreamName.for_deployment(deployment)
  end

  def websocket_mailbox_items
    @test_case.broadcasts(stream_name)
  end

  def capture_websocket_mailbox_items(&block)
    @test_case.capture_broadcasts(stream_name, &block)
  end

  def poll!(limit: 10)
    program_response = post_and_parse(
      "/program_api/control/poll",
      params: { limit: limit },
      headers: @test_case.send(:program_api_headers, @machine_credential)
    )
    execution_response = execution_machine_credential.present? ? poll_execution!(limit: limit) : nil

    {
      "mailbox_items" => merge_mailbox_items(
        program_response.fetch("mailbox_items", []),
        execution_response&.fetch("mailbox_items", []) || []
      ),
    }
  end

  def report!(method_id:, **params)
    if execution_report?(method_id:, params:)
      raise ArgumentError, "execution_machine_credential is required for #{method_id}" if execution_machine_credential.blank?

      return post_and_parse(
        "/execution_api/control/report",
        params: params.merge(method_id: method_id),
        headers: @test_case.send(:execution_api_headers, execution_machine_credential)
      )
    end

    post_and_parse(
      "/program_api/control/report",
      params: params.merge(method_id: method_id),
      headers: @test_case.send(:program_api_headers, @machine_credential)
    )
  end

  private

  attr_reader :execution_machine_credential

  def poll_execution!(limit:)
    post_and_parse(
      "/execution_api/control/poll",
      params: { limit: limit },
      headers: @test_case.send(:execution_api_headers, execution_machine_credential)
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
end
