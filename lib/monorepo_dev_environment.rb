# frozen_string_literal: true

module MonorepoDevEnvironment
  CORE_MATRIX_PORT = "3000"
  AGENT_FENIX_PORT = "36173"
  AGENT_FENIX_HOST = "127.0.0.1"

  module_function

  def defaults(base_env = ENV)
    core_matrix_port = base_env.fetch("CORE_MATRIX_PORT", base_env.fetch("PORT", CORE_MATRIX_PORT))
    agent_fenix_port = base_env.fetch("AGENT_FENIX_PORT", AGENT_FENIX_PORT)

    {
      "PORT" => base_env.fetch("PORT", core_matrix_port),
      "CORE_MATRIX_PORT" => core_matrix_port,
      "AGENT_FENIX_PORT" => agent_fenix_port,
      "AGENT_FENIX_BASE_URL" => base_env.fetch("AGENT_FENIX_BASE_URL", "http://#{AGENT_FENIX_HOST}:#{agent_fenix_port}")
    }
  end
end
