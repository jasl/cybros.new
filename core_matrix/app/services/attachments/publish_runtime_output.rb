module Attachments
  class PublishRuntimeOutput
    InvalidParameters = Class.new(StandardError) do
      attr_reader :reason

      def initialize(reason:)
        @reason = reason
        super(reason)
      end
    end

    def self.call(...)
      new(...).call
    end

    def initialize(turn:, files:, publication_role: nil)
      @turn = turn
      @files = files
      @publication_role = publication_role
    end

    def call
      attachments = nil

      Turns::WithTimelineMutationLock.call(
        turn: @turn,
        retained_message: "must be retained before publishing runtime artifacts",
        active_message: "must belong to an active conversation to publish runtime artifacts",
        closing_message: "must not publish runtime artifacts while close is in progress",
        interrupted_message: "must not publish runtime artifacts after turn interruption"
      ) do |locked_turn|
        raise InvalidParameters.new(reason: "artifact_ingress_not_allowed") unless locked_turn.conversation.allows_entry_surface?("artifact_ingress")
        output_message = locked_turn.selected_output_message || raise(InvalidParameters.new(reason: "selected_output_message_missing"))
        raise InvalidParameters.new(reason: "turn_not_completed") unless locked_turn.completed?
        raise InvalidParameters.new(reason: "publication_role_required") if @publication_role.blank?
        raise InvalidParameters.new(reason: "files_missing") if @files.blank?

        attachments = Attachments::CreateForMessage.call(
          message: output_message,
          files: @files,
          source_kind: "runtime_generated",
          publication_role: @publication_role
        )
      end

      attachments
    end
  end
end
