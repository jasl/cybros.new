module AgentControl
  class Report
    StaleReportError = Class.new(StandardError)

    Result = Struct.new(:code, :http_status, :mailbox_items, keyword_init: true)

    def self.call(...)
      new(...).call
    end

    def initialize(deployment:, agent_session: nil, execution_session: nil, resource: nil, method_id: nil, protocol_message_id: nil, payload: nil, occurred_at: Time.current, **kwargs)
      raw_payload = payload.presence || kwargs
      @deployment = deployment
      @agent_session = agent_session
      @execution_session = execution_session
      @resource = resource
      @payload = raw_payload.deep_stringify_keys
      @method_id = method_id || @payload.fetch("method_id")
      @protocol_message_id = protocol_message_id || @payload.fetch("protocol_message_id")
      @occurred_at = occurred_at
    end

    def call
      @resolved_agent_session = TouchDeploymentActivity.call(
        deployment: @deployment,
        agent_session: @agent_session,
        occurred_at: @occurred_at
      )

      result_code = nil

      ApplicationRecord.transaction do
        receipt = create_receipt!

        begin
          process_report!(receipt)
          receipt.update_columns(result_code: "accepted", updated_at: Time.current)
          result_code = "accepted"
        rescue StaleReportError
          receipt.update_columns(result_code: "stale", updated_at: Time.current)
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
      receipt = AgentControlReportReceipt.new(
        installation_id: @deployment.installation_id,
        agent_session: resolved_agent_session,
        execution_session: @execution_session,
        protocol_message_id: @protocol_message_id,
        method_id: @method_id,
        logical_work_id: @payload["logical_work_id"],
        attempt_no: @payload["attempt_no"],
        result_code: "processing",
      )
      receipt.payload = @payload
      receipt.send(:materialize_pending_payload)
      receipt.save!(validate: false)
      receipt
    end

    def find_existing_receipt
      AgentControlReportReceipt.find_by(installation_id: @deployment.installation_id, protocol_message_id: @protocol_message_id)
    end

    def process_report!(receipt)
      handler = report_handler
      persist_receipt_attributes!(receipt, handler.receipt_attributes)
      handler.call
    end

    def report_handler
      @report_handler ||= ReportDispatch.call(
        deployment: @deployment,
        agent_session: resolved_agent_session,
        execution_session: @execution_session,
        resource: @resource,
        method_id: @method_id,
        payload: @payload,
        occurred_at: @occurred_at
      )
    end

    def resolved_agent_session
      @resolved_agent_session ||= @agent_session || @deployment.active_agent_session || @deployment.most_recent_agent_session
    end

    def persist_receipt_attributes!(receipt, attrs)
      normalized_attrs = normalize_receipt_attributes(attrs)
      return if normalized_attrs.blank?

      receipt.update_columns(normalized_attrs.merge(updated_at: Time.current))
    end

    def normalize_receipt_attributes(attrs)
      attrs.to_h.compact.each_with_object({}) do |(key, value), normalized|
        reflection = AgentControlReportReceipt.reflect_on_association(key)
        if reflection.present?
          normalized[reflection.foreign_key] = value&.id
        else
          normalized[key] = value
        end
      end
    end

    def follow_up_mailbox_items
      poll_arguments = {
        limit: Poll::DEFAULT_LIMIT,
        occurred_at: @occurred_at,
      }

      if @execution_session.present?
        Poll.call(execution_session: @execution_session, **poll_arguments)
      else
        Poll.call(deployment: @deployment, agent_session: resolved_agent_session, **poll_arguments)
      end
    end
  end
end
