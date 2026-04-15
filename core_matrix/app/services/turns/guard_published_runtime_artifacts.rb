module Turns
  class GuardPublishedRuntimeArtifacts
    DEFAULT_MESSAGE = "must not replace the selected output after runtime artifacts were published".freeze

    def self.call(...)
      new(...).call
    end

    def initialize(turn:, attribute: :base, message: DEFAULT_MESSAGE)
      @turn = turn
      @attribute = attribute
      @message = message
    end

    def call
      selected_output_message = current_selected_output_message
      return if selected_output_message.blank?
      return unless runtime_artifacts_published?(selected_output_message)

      @turn.errors.add(@attribute, @message)
      raise ActiveRecord::RecordInvalid, @turn
    end

    private

    def current_selected_output_message
      return if @turn.selected_output_message_id.blank?

      Message
        .includes(message_attachments: { file_attachment: :blob })
        .find(@turn.selected_output_message_id)
    end

    def runtime_artifacts_published?(message)
      message.message_attachments.any? do |attachment|
        Attachments::CreateForMessage.source_kind_for(attachment) == "runtime_generated"
      end
    end
  end
end
