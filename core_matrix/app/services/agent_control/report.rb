module AgentControl
  class Report
    StaleReportError = Class.new(StandardError)

    Result = Struct.new(:code, :http_status, :mailbox_items, keyword_init: true)

    def self.call(...)
      new(...).call
    end

    def initialize(deployment:, agent_session: nil, execution_session: nil, method_id: nil, protocol_message_id: nil, payload: nil, occurred_at: Time.current, **kwargs)
      raw_payload = payload.presence || kwargs
      @deployment = deployment
      @agent_session = agent_session
      @execution_session = execution_session
      @payload = raw_payload.deep_stringify_keys
      @method_id = method_id || @payload.fetch("method_id")
      @protocol_message_id = protocol_message_id || @payload.fetch("protocol_message_id")
      @occurred_at = occurred_at
    end

    def call
      TouchDeploymentActivity.call(deployment: @deployment, agent_session: @agent_session, occurred_at: @occurred_at)

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
        mailbox_items: result_code == "stale" ? [] : follow_up_mailbox_items
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
        mailbox_items: code == "stale" ? [] : follow_up_mailbox_items
      )
    end

    def create_receipt!
      AgentControlReportReceipt.create!(
        installation: @deployment.installation,
        agent_session: resolved_agent_session,
        execution_session: @execution_session,
        protocol_message_id: @protocol_message_id,
        method_id: @method_id,
        logical_work_id: @payload["logical_work_id"],
        attempt_no: @payload["attempt_no"],
        result_code: "processing",
        payload: @payload
      )
    end

    def find_existing_receipt
      AgentControlReportReceipt.find_by(installation_id: @deployment.installation_id, protocol_message_id: @protocol_message_id)
    end

    def process_report!(receipt)
      handler = report_handler
      receipt.update!(handler.receipt_attributes.compact) if handler.receipt_attributes.present?
      handler.call
    end

    def report_handler
      @report_handler ||= ReportDispatch.call(
        deployment: @deployment,
        agent_session: resolved_agent_session,
        execution_session: @execution_session,
        method_id: @method_id,
        payload: @payload,
        occurred_at: @occurred_at
      )
    end

    def resolved_agent_session
      @resolved_agent_session ||= @agent_session || @deployment.active_agent_session || @deployment.most_recent_agent_session
    end

    def follow_up_mailbox_items
      poll_arguments = {
        limit: Poll::DEFAULT_LIMIT,
        occurred_at: @occurred_at,
      }

      if @execution_session.present?
        Poll.call(execution_session: @execution_session, **poll_arguments)
      else
        Poll.call(deployment: @deployment, **poll_arguments)
      end
    end
  end
end
