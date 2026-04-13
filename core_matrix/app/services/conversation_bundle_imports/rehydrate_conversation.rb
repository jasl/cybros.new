module ConversationBundleImports
  class RehydrateConversation
    def self.call(...)
      new(...).call
    end

    def initialize(request:, parsed_bundle:)
      @request = request
      @parsed_bundle = parsed_bundle
    end

    def call
      ApplicationRecord.transaction do
        conversation = Conversations::CreateRoot.call(
          workspace: @request.workspace,
          agent: target_agent_definition_version.agent
        )
        restore_conversation_timestamps!(conversation)
        rehydrate_turns!(conversation)
        conversation
      end
    end

    private

    def target_agent_definition_version
      @target_agent_definition_version ||= AgentDefinitionVersion.find_by!(
        installation_id: @request.installation_id,
        public_id: @request.request_payload.fetch("target_agent_definition_version_id")
      )
    end

    def conversation_payload
      @parsed_bundle.fetch("conversation_payload")
    end

    def file_bytes
      @parsed_bundle.fetch("file_bytes")
    end

    def target_execution_runtime
      @target_execution_runtime ||= target_agent_definition_version.agent.default_execution_runtime
    end

    def restore_conversation_timestamps!(conversation)
      created_at = parse_time(conversation_payload.dig("conversation", "created_at"), fallback: conversation.created_at)
      updated_at = parse_time(conversation_payload.dig("conversation", "updated_at"), fallback: conversation.updated_at)

      conversation.update_columns(
        created_at: created_at,
        updated_at: updated_at
      )
    end

    def rehydrate_turns!(conversation)
      grouped_messages = conversation_payload.fetch("messages").group_by { |message| message.fetch("turn_public_id") }
      ordered_turn_ids = conversation_payload.fetch("messages").map { |message| message.fetch("turn_public_id") }.uniq
      message_map = {}
      attachment_map = {}
      deferred_origins = []

      ordered_turn_ids.each_with_index do |source_turn_public_id, index|
        message_group = grouped_messages.fetch(source_turn_public_id)
        input_payload = message_group.find { |message| message.fetch("slot") == "input" }
        output_payload = message_group.find { |message| message.fetch("slot") == "output" }
        created_at = parse_time(input_payload&.fetch("created_at", nil) || output_payload&.fetch("created_at", nil), fallback: Time.current)
        updated_at = parse_time(output_payload&.fetch("updated_at", nil) || input_payload&.fetch("updated_at", nil), fallback: created_at)
        execution_identity = Turns::FreezeExecutionIdentity.call(
          conversation: conversation,
          execution_runtime: target_execution_runtime,
          allow_unavailable_execution_runtime: true
        )

        turn = Turn.create!(
          installation: conversation.installation,
          conversation: conversation,
          agent_definition_version: execution_identity.agent_definition_version,
          execution_runtime: execution_identity.execution_runtime,
          execution_runtime_version: execution_identity.execution_runtime_version,
          sequence: index + 1,
          lifecycle_state: "completed",
          origin_kind: "system_internal",
          origin_payload: {
            "import_request_id" => @request.public_id,
            "source_bundle_kind" => conversation_payload.fetch("bundle_kind"),
          },
          source_ref_type: "ConversationBundleImportRequest",
          source_ref_id: @request.public_id,
          pinned_agent_definition_fingerprint: execution_identity.pinned_agent_definition_fingerprint,
          agent_config_version: execution_identity.agent_config_version,
          agent_config_content_fingerprint: execution_identity.agent_config_content_fingerprint,
          resolved_config_snapshot: {},
          resolved_model_selection_snapshot: {},
          created_at: created_at,
          updated_at: updated_at
        )

        input_message = create_message_from_payload(
          turn: turn,
          payload: input_payload,
          message_map: message_map,
          attachment_map: attachment_map,
          deferred_origins: deferred_origins
        ) if input_payload.present?
        output_message = create_message_from_payload(
          turn: turn,
          payload: output_payload,
          source_input_message: input_message,
          message_map: message_map,
          attachment_map: attachment_map,
          deferred_origins: deferred_origins
        ) if output_payload.present?

        turn.update!(
          selected_input_message: input_message,
          selected_output_message: output_message
        )
        turn.update_columns(created_at: created_at, updated_at: updated_at)
      end

      apply_attachment_origins!(deferred_origins:, message_map:, attachment_map:)
      conversation.refresh_latest_anchors!
    end

    def create_message_from_payload(turn:, payload:, source_input_message: nil, message_map:, attachment_map:, deferred_origins:)
      message_class = payload.fetch("role") == "user" ? UserMessage : AgentMessage
      created_at = parse_time(payload.fetch("created_at"), fallback: Time.current)
      updated_at = parse_time(payload.fetch("updated_at"), fallback: created_at)

      message = message_class.create!(
        installation: turn.installation,
        conversation: turn.conversation,
        turn: turn,
        role: payload.fetch("role"),
        slot: payload.fetch("slot"),
        variant_index: payload.fetch("variant_index"),
        content: payload.fetch("content"),
        source_input_message: source_input_message,
        created_at: created_at,
        updated_at: updated_at
      )
      message_map[payload.fetch("message_public_id")] = message

      payload.fetch("attachments").each do |attachment_payload|
        attachment = MessageAttachment.new(
          installation: turn.installation,
          conversation: turn.conversation,
          message: message
        )
        attachment.file.attach(
          io: StringIO.new(file_bytes.fetch(attachment_payload.fetch("relative_path"))),
          filename: attachment_payload.fetch("filename"),
          content_type: attachment_payload.fetch("mime_type"),
          identify: false
        )
        attachment.save!
        attachment_map[attachment_payload.fetch("attachment_public_id")] = attachment
        deferred_origins << {
          "attachment" => attachment,
          "origin_attachment_public_id" => attachment_payload["origin_attachment_public_id"],
          "origin_message_public_id" => attachment_payload["origin_message_public_id"],
        }
      end

      message.update_columns(created_at: created_at, updated_at: updated_at)
      message
    end

    def apply_attachment_origins!(deferred_origins:, message_map:, attachment_map:)
      deferred_origins.each do |entry|
        attachment = entry.fetch("attachment")
        origin_attachment = attachment_map[entry["origin_attachment_public_id"]]
        origin_message = message_map[entry["origin_message_public_id"]] || origin_attachment&.origin_message || origin_attachment&.message
        next if origin_attachment.blank? && origin_message.blank?

        attachment.update!(
          origin_attachment: origin_attachment,
          origin_message: origin_message
        )
      end
    end

    def parse_time(value, fallback:)
      return fallback if value.blank?

      Time.iso8601(value)
    rescue ArgumentError
      fallback
    end
  end
end
