module Runtime
  class ProgramToolsController < ApplicationController
    def execute
      result = Fenix::Runtime::ExecuteProgramTool.call(payload: request_payload)

      render json: result, status: status_for(result)
    end

    private

    def request_payload
      params.to_unsafe_h.except("controller", "action")
    end

    def status_for(result)
      return :ok if result.fetch("status") == "completed"

      result.dig("error", "classification") == "runtime" ? :internal_server_error : :unprocessable_entity
    end
  end
end
