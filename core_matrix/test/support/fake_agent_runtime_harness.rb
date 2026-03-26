class FakeAgentRuntimeHarness
  def initialize(test_case:, deployment:, machine_credential:)
    @test_case = test_case
    @deployment = deployment
    @machine_credential = machine_credential
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
    @test_case.post(
      "/agent_api/control/poll",
      params: { limit: limit },
      headers: @test_case.send(:agent_api_headers, @machine_credential),
      as: :json
    )

    parse_response
  end

  def report!(method_id:, **params)
    @test_case.post(
      "/agent_api/control/report",
      params: params.merge(method_id: method_id),
      headers: @test_case.send(:agent_api_headers, @machine_credential),
      as: :json
    )

    parse_response.merge("http_status" => @test_case.response.status)
  end

  private

  def parse_response
    body = @test_case.response.body
    body.present? ? JSON.parse(body) : {}
  end
end
