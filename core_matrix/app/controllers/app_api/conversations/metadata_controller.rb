module AppAPI
  module Conversations
    class MetadataController < AppAPI::Conversations::BaseController
      def show
        render_method_response(
          method_id: "conversation_metadata_show",
          metadata: metadata_payload(@conversation)
        )
      end

      def update
        updated_conversation = ::Conversations::Metadata::UserEdit.call(
          conversation: @conversation,
          **metadata_update_params
        )

        render_method_response(
          method_id: "conversation_metadata_update",
          metadata: metadata_payload(updated_conversation)
        )
      end

      def regenerate
        updated_conversation = ::Conversations::Metadata::Regenerate.call(
          conversation: @conversation,
          field: params.fetch(:field)
        )

        render_method_response(
          method_id: "conversation_metadata_regenerate",
          metadata: metadata_payload(updated_conversation)
        )
      end

      private

      def metadata_update_params
        params.permit(:title, :summary).to_h.symbolize_keys
      end

      def metadata_payload(conversation)
        {
          "conversation_id" => conversation.public_id,
          "title" => conversation.title,
          "summary" => conversation.summary,
          "title_source" => conversation.title_source,
          "summary_source" => conversation.summary_source,
          "title_locked" => conversation.title_locked?,
          "summary_locked" => conversation.summary_locked?,
        }
      end
    end
  end
end
