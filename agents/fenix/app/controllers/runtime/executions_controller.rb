module Runtime
  class ExecutionsController < ApplicationController
    def create
      runtime_execution = RuntimeExecution.find_or_create_by!(
        mailbox_item_id: request.request_parameters.fetch("item_id"),
        attempt_no: request.request_parameters.fetch("attempt_no")
      ) do |execution|
        execution.protocol_message_id = request.request_parameters.fetch("protocol_message_id")
        execution.logical_work_id = request.request_parameters.fetch("logical_work_id")
        execution.runtime_plane = request.request_parameters.fetch("runtime_plane")
        execution.mailbox_item_payload = request.request_parameters.deep_dup
      end

      RuntimeExecutionJob.perform_later(runtime_execution.id) if runtime_execution.previously_new_record?

      render json: serialize_runtime_execution(runtime_execution), status: :accepted
    end

    def show
      runtime_execution = RuntimeExecution.find_by!(execution_id: params[:id])

      render json: serialize_runtime_execution(runtime_execution)
    end

    private

    def serialize_runtime_execution(runtime_execution)
      {
        execution_id: runtime_execution.execution_id,
        status: runtime_execution.status,
        output: runtime_execution.output_payload,
        error: runtime_execution.error_payload,
        reports: runtime_execution.reports,
        trace: runtime_execution.trace,
        mailbox_item_id: runtime_execution.mailbox_item_id,
        logical_work_id: runtime_execution.logical_work_id,
        attempt_no: runtime_execution.attempt_no,
        runtime_plane: runtime_execution.runtime_plane,
        started_at: runtime_execution.started_at,
        finished_at: runtime_execution.finished_at,
      }.compact
    end
  end
end
