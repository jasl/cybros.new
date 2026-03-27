module AgentControl
  class Report
    StaleReportError = Class.new(StandardError)

    Result = Struct.new(:code, :http_status, :mailbox_items, keyword_init: true)

    def self.call(...)
      new(...).call
    end

    def initialize(deployment:, method_id: nil, message_id: nil, payload: nil, occurred_at: Time.current, **kwargs)
      raw_payload = payload.presence || kwargs
      @deployment = deployment
      @payload = raw_payload.deep_stringify_keys
      @method_id = method_id || @payload.fetch("method_id")
      @message_id = message_id || @payload.fetch("message_id")
      @occurred_at = occurred_at
    end

    def call
      TouchDeploymentActivity.call(deployment: @deployment, occurred_at: @occurred_at)

      existing_receipt = find_existing_receipt
      return duplicate_result_for(existing_receipt) if existing_receipt.present?

      result_code = nil

      ApplicationRecord.transaction do
        receipt = create_receipt!

        begin
          process_report!(receipt)
          receipt.update!(result_code: "accepted")
          result_code = "accepted"
        rescue StaleReportError
          receipt.update!(result_code: "stale")
          result_code = "stale"
        end
      end

      Result.new(
        code: result_code,
        http_status: result_code == "stale" ? :conflict : :ok,
        mailbox_items: result_code == "stale" ? [] : Poll.call(deployment: @deployment, limit: Poll::DEFAULT_LIMIT, occurred_at: @occurred_at)
      )
    rescue ActiveRecord::RecordNotUnique
      duplicate_result_for(find_existing_receipt)
    end

    private

    def duplicate_result_for(receipt)
      code = receipt.result_code == "accepted" ? "duplicate" : receipt.result_code
      Result.new(
        code: code,
        http_status: code == "stale" ? :conflict : :ok,
        mailbox_items: code == "stale" ? [] : Poll.call(deployment: @deployment, limit: Poll::DEFAULT_LIMIT, occurred_at: @occurred_at)
      )
    end

    def create_receipt!
      AgentControlReportReceipt.create!(
        installation: @deployment.installation,
        agent_deployment: @deployment,
        message_id: @message_id,
        method_id: @method_id,
        logical_work_id: @payload["logical_work_id"],
        attempt_no: @payload["attempt_no"],
        result_code: "processing",
        payload: @payload
      )
    end

    def find_existing_receipt
      AgentControlReportReceipt.find_by(installation_id: @deployment.installation_id, message_id: @message_id)
    end

    def process_report!(receipt)
      handler = report_handler
      receipt.update!(handler.receipt_attributes.compact) if handler.receipt_attributes.present?
      handler.call
    end

    def report_handler
      @report_handler ||= ReportDispatch.call(
        deployment: @deployment,
        method_id: @method_id,
        payload: @payload,
        occurred_at: @occurred_at
      )
    end
  end
end
