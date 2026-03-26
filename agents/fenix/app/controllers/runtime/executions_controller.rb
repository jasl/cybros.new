module Runtime
  class ExecutionsController < ApplicationController
    def create
      result = Fenix::Runtime::ExecuteAssignment.call(
        mailbox_item: request.request_parameters
      )

      render json: serialize_result(result), status: http_status_for(result)
    end

    private

    def serialize_result(result)
      {
        status: result.status,
        output: result.output,
        error: result.error,
        reports: result.reports,
        trace: result.trace,
      }.compact
    end

    def http_status_for(result)
      result.status == "failed" ? :unprocessable_entity : :ok
    end
  end
end
