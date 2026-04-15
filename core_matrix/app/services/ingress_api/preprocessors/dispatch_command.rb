module IngressAPI
  module Preprocessors
    class DispatchCommand
      def self.call(...)
        new(...).call
      end

      def initialize(context:)
        @context = context
      end

      def call
        @context.append_trace("dispatch_command")
        parsed = IngressCommands::Parse.call(text: @context.envelope.text)
        return @context unless parsed.command?

        @context.command = parsed
        authorization = IngressCommands::Authorize.call(
          command: parsed,
          context: @context,
          sender_external_id: @context.envelope.external_sender_id
        )
        @context.authorization_result = authorization

        unless authorization.allowed?
          @context.result = IngressAPI::Result.rejected(
            rejection_reason: authorization.rejection_reason,
            trace: @context.pipeline_trace,
            envelope: @context.envelope,
            conversation: @context.conversation,
            channel_session: @context.channel_session,
            command_name: parsed.name,
            request_metadata: @context.request_metadata
          )
          return @context
        end

        @context.result = IngressCommands::Dispatch.call(command: parsed, context: @context)
        @context
      end
    end
  end
end
