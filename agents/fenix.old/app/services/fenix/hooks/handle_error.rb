module Fenix
  module Hooks
    class HandleError
      def self.call(error:, logical_work_id:, attempt_no:)
        {
          "failure_kind" => "runtime_error",
          "retryable" => false,
          "logical_work_id" => logical_work_id,
          "attempt_no" => attempt_no,
          "last_error_summary" => error.message,
        }
      end
    end
  end
end
