module IngressAPI
  class MaterializeTurnEntry
    Result = Struct.new(:conversation, :turn, :message, keyword_init: true)

    def self.call(...)
      new(...).call
    end

    def initialize(
      conversation:,
      channel_inbound_message:,
      content:,
      origin_payload:,
      selector_source:,
      selector:,
      execution_runtime: nil,
      bootstrap_title: true,
      attachment_records: []
    )
      @conversation = conversation
      @channel_inbound_message = channel_inbound_message
      @content = content
      @origin_payload = origin_payload
      @selector_source = selector_source
      @selector = selector
      @execution_runtime = execution_runtime
      @bootstrap_title = bootstrap_title
      @attachment_records = Array(attachment_records)
    end

    def call
      turn = Turns::StartChannelIngressTurn.call(
        conversation: @conversation,
        channel_inbound_message: @channel_inbound_message,
        content: @content,
        origin_payload: @origin_payload,
        selector_source: @selector_source,
        selector: @selector,
        execution_runtime: @execution_runtime
      )
      enqueue_materialization(turn)
      enqueue_title_bootstrap(turn) if @bootstrap_title
      IngressAPI::AttachMaterializedAttachments.call(
        message: turn.selected_input_message,
        attachment_records: @attachment_records
      )

      Result.new(
        conversation: @conversation,
        turn: turn,
        message: turn.selected_input_message
      )
    end

    private

    def enqueue_materialization(turn)
      Turns::MaterializeAndDispatchJob.perform_later(turn.public_id)
    rescue StandardError => error
      Rails.logger.warn("channel ingress workflow bootstrap enqueue failed for #{turn.public_id}: #{error.class}: #{error.message}")
    end

    def enqueue_title_bootstrap(turn)
      Conversations::Metadata::BootstrapTitleJob.perform_later(@conversation.public_id, turn.public_id)
    rescue StandardError => error
      Rails.logger.warn("channel ingress title bootstrap enqueue failed for #{@conversation.public_id}/#{turn.public_id}: #{error.class}: #{error.message}")
    end
  end
end
