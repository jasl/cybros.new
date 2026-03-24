#!/usr/bin/env ruby

require "json"
require "net/http"
require "uri"

class DummyAgentRuntime
  DEFAULT_PROTOCOL_METHODS = [
    { "method_id" => "agent_health" },
    { "method_id" => "capabilities_handshake" },
  ].freeze
  DEFAULT_TOOL_CATALOG = [
    {
      "tool_name" => "shell_exec",
      "tool_kind" => "kernel_primitive",
      "implementation_source" => "kernel",
      "implementation_ref" => "kernel/shell_exec",
      "input_schema" => { "type" => "object", "properties" => {} },
      "result_schema" => { "type" => "object", "properties" => {} },
      "streaming_support" => false,
      "idempotency_policy" => "best_effort",
    },
  ].freeze

  def self.run(argv)
    new(argv).run
  end

  def initialize(argv)
    @argv = argv.dup
    @command = @argv.shift
  end

  def run
    case @command
    when "register"
      request_json(:post, "/agent_api/registrations", register_payload)
    when "heartbeat"
      request_json(:post, "/agent_api/heartbeats", heartbeat_payload, machine_credential: machine_credential)
    when "capabilities"
      request_json(:post, "/agent_api/capabilities", capabilities_payload, machine_credential: machine_credential)
    when "health"
      request_json(:get, "/agent_api/health", nil, machine_credential: machine_credential)
    else
      abort usage
    end
  end

  private

  def request_json(method, path, payload, machine_credential: nil)
    uri = URI.join(base_url, path)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"

    request_class = request_class_for(method)
    request = request_class.new(uri)
    request["Accept"] = "application/json"
    request["Content-Type"] = "application/json"
    request["Authorization"] = "Token token=\"#{machine_credential}\"" if machine_credential
    request.body = JSON.generate(payload) if payload

    response = http.request(request)
    body = response.body.to_s
    parsed_body =
      if body.empty?
        {}
      else
        JSON.parse(body)
      end

    puts JSON.pretty_generate(
      {
        "status" => response.code.to_i,
        "body" => parsed_body,
      }
    )
  end

  def register_payload
    {
      "enrollment_token" => ENV.fetch("CORE_MATRIX_ENROLLMENT_TOKEN"),
      "fingerprint" => ENV.fetch("CORE_MATRIX_FINGERPRINT", "dummy-runtime"),
      "endpoint_metadata" => {
        "transport" => "http",
        "base_url" => runtime_base_url,
      },
      "protocol_version" => ENV.fetch("CORE_MATRIX_PROTOCOL_VERSION", "2026-03-24"),
      "sdk_version" => ENV.fetch("CORE_MATRIX_SDK_VERSION", "dummy-runtime-0.1.0"),
      "protocol_methods" => DEFAULT_PROTOCOL_METHODS,
      "tool_catalog" => DEFAULT_TOOL_CATALOG,
      "config_schema_snapshot" => {
        "type" => "object",
        "properties" => {
          "interactive" => {
            "type" => "object",
            "properties" => {
              "selector" => { "type" => "string" },
            },
          },
        },
      },
      "conversation_override_schema_snapshot" => {
        "type" => "object",
        "properties" => {},
      },
      "default_config_snapshot" => {
        "sandbox" => "workspace-write",
        "interactive" => {
          "selector" => "role:main",
        },
      },
    }
  end

  def heartbeat_payload
    {
      "health_status" => ENV.fetch("CORE_MATRIX_HEALTH_STATUS", "healthy"),
      "health_metadata" => {
        "runtime" => "dummy_agent_runtime",
      },
      "auto_resume_eligible" => truthy?(ENV.fetch("CORE_MATRIX_AUTO_RESUME_ELIGIBLE", "true")),
      "unavailability_reason" => ENV["CORE_MATRIX_UNAVAILABILITY_REASON"],
    }.compact
  end

  def capabilities_payload
    {
      "fingerprint" => ENV.fetch("CORE_MATRIX_FINGERPRINT", "dummy-runtime"),
      "protocol_version" => ENV.fetch("CORE_MATRIX_PROTOCOL_VERSION", "2026-03-24"),
      "sdk_version" => ENV.fetch("CORE_MATRIX_SDK_VERSION", "dummy-runtime-0.1.0"),
      "protocol_methods" => DEFAULT_PROTOCOL_METHODS,
      "tool_catalog" => DEFAULT_TOOL_CATALOG,
      "config_schema_snapshot" => register_payload.fetch("config_schema_snapshot"),
      "conversation_override_schema_snapshot" => register_payload.fetch("conversation_override_schema_snapshot"),
      "default_config_snapshot" => register_payload.fetch("default_config_snapshot"),
    }
  end

  def request_class_for(method)
    case method
    when :get then Net::HTTP::Get
    when :post then Net::HTTP::Post
    else
      raise ArgumentError, "unsupported method #{method.inspect}"
    end
  end

  def machine_credential
    ENV.fetch("CORE_MATRIX_MACHINE_CREDENTIAL")
  end

  def base_url
    ENV.fetch("CORE_MATRIX_BASE_URL", "http://127.0.0.1:3000")
  end

  def runtime_base_url
    ENV.fetch("CORE_MATRIX_RUNTIME_BASE_URL", "http://127.0.0.1:4100")
  end

  def truthy?(value)
    value.to_s == "true"
  end

  def usage
    <<~TEXT
      Usage:
        ruby script/manual/dummy_agent_runtime.rb register
        ruby script/manual/dummy_agent_runtime.rb heartbeat
        ruby script/manual/dummy_agent_runtime.rb capabilities
        ruby script/manual/dummy_agent_runtime.rb health

      Environment:
        CORE_MATRIX_BASE_URL
        CORE_MATRIX_RUNTIME_BASE_URL
        CORE_MATRIX_ENROLLMENT_TOKEN     # required for register
        CORE_MATRIX_MACHINE_CREDENTIAL   # required for heartbeat/capabilities/health
        CORE_MATRIX_FINGERPRINT
        CORE_MATRIX_PROTOCOL_VERSION
        CORE_MATRIX_SDK_VERSION
        CORE_MATRIX_HEALTH_STATUS
        CORE_MATRIX_AUTO_RESUME_ELIGIBLE
        CORE_MATRIX_UNAVAILABILITY_REASON
    TEXT
  end
end

DummyAgentRuntime.run(ARGV)
