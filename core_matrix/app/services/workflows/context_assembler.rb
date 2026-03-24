module Workflows
  class ContextAssembler
    def self.call(...)
      new(...).call
    end

    def initialize(turn:)
      @turn = turn
    end

    def call
      raise_invalid!("requires a resolved provider handle") if @turn.resolved_provider_handle.blank?
      raise_invalid!("requires a resolved model ref") if @turn.resolved_model_ref.blank?

      attachment_manifest = build_attachment_manifest
      {
        "config" => @turn.effective_config_snapshot,
        "execution_context" => {
          "identity" => execution_identity,
          "turn_origin" => turn_origin,
          "context_messages" => context_messages,
          "context_imports" => context_imports,
          "attachment_manifest" => attachment_manifest,
          "runtime_attachment_manifest" => build_runtime_attachment_manifest(attachment_manifest),
          "model_input_attachments" => build_model_input_attachments(attachment_manifest),
          "attachment_diagnostics" => build_attachment_diagnostics(attachment_manifest),
        },
      }
    end

    private

    def execution_identity
      {
        "user_id" => @turn.conversation.workspace.user_id.to_s,
        "workspace_id" => @turn.conversation.workspace_id.to_s,
        "conversation_id" => @turn.conversation_id.to_s,
        "turn_id" => @turn.id.to_s,
        "agent_deployment_id" => @turn.agent_deployment_id.to_s,
      }
    end

    def turn_origin
      {
        "origin_kind" => @turn.origin_kind,
        "origin_payload" => @turn.origin_payload,
        "source_ref_type" => @turn.source_ref_type,
        "source_ref_id" => @turn.source_ref_id,
      }
    end

    def context_messages
      visible_context_messages.filter_map do |message|
        next unless message.is_a?(Message)

        {
          "message_id" => message.id.to_s,
          "conversation_id" => message.conversation_id.to_s,
          "turn_id" => message.turn_id.to_s,
          "role" => message.role,
          "slot" => message.slot,
          "content" => message.content,
        }
      end
    end

    def context_imports
      @turn.conversation.conversation_imports
        .includes(:source_conversation, :source_message, :summary_segment)
        .order(:id)
        .filter_map do |conversation_import|
          next if conversation_import.summary_segment&.superseded_by_id.present?

          {
            "import_id" => conversation_import.id.to_s,
            "kind" => conversation_import.kind,
            "source_conversation_id" => conversation_import.source_conversation_id&.to_s,
            "source_message_id" => conversation_import.source_message_id&.to_s,
            "summary_segment_id" => conversation_import.summary_segment_id&.to_s,
            "content" => imported_content(conversation_import),
          }.compact
        end
    end

    def build_attachment_manifest
      visible_context_messages.flat_map { |message| message.message_attachments.order(:id).to_a }.map do |attachment|
        {
          "attachment_id" => attachment.id.to_s,
          "source_message_id" => attachment.message_id.to_s,
          "origin_attachment_id" => attachment.origin_attachment_id&.to_s,
          "origin_message_id" => attachment.origin_message_id&.to_s,
          "filename" => attachment.file.filename.to_s,
          "content_type" => attachment.file.blob.content_type,
          "byte_size" => attachment.file.blob.byte_size,
          "modality" => modality_for(attachment.file.blob.content_type),
          "runtime_ref" => runtime_ref_for(attachment),
        }.compact
      end
    end

    def build_runtime_attachment_manifest(attachment_manifest)
      attachment_manifest.map do |entry|
        entry.slice(
          "attachment_id",
          "source_message_id",
          "filename",
          "content_type",
          "byte_size",
          "runtime_ref"
        )
      end
    end

    def build_model_input_attachments(attachment_manifest)
      attachment_manifest.filter_map do |entry|
        next unless modality_supported?(entry.fetch("modality"))

        entry.slice(
          "attachment_id",
          "source_message_id",
          "filename",
          "content_type",
          "byte_size",
          "modality"
        )
      end
    end

    def build_attachment_diagnostics(attachment_manifest)
      attachment_manifest.filter_map do |entry|
        next if modality_supported?(entry.fetch("modality"))

        {
          "attachment_id" => entry.fetch("attachment_id"),
          "reason" => "unsupported_modality",
          "modality" => entry.fetch("modality"),
          "content_type" => entry.fetch("content_type"),
        }
      end
    end

    def visible_context_messages
      @visible_context_messages ||= @turn.conversation.context_projection_messages.select do |message|
        message.conversation_id != @turn.conversation_id || message.turn.sequence <= @turn.sequence
      end
    end

    def imported_content(conversation_import)
      return conversation_import.summary_segment.content if conversation_import.summary_segment.present?
      return conversation_import.source_message.content if conversation_import.source_message.present?

      nil
    end

    def runtime_ref_for(attachment)
      {
        "kind" => "message_attachment",
        "attachment_id" => attachment.id.to_s,
        "blob_id" => attachment.file.blob.id.to_s,
      }
    end

    def modality_for(content_type)
      return "image" if content_type.start_with?("image/")
      return "audio" if content_type.start_with?("audio/")
      return "video" if content_type.start_with?("video/")

      "file"
    end

    def modality_supported?(modality)
      catalog
        .model(@turn.resolved_provider_handle, @turn.resolved_model_ref)
        .dig(:capabilities, :multimodal_inputs, modality.to_sym) == true
    end

    def catalog
      @catalog ||= ProviderCatalog::Load.call
    end

    def raise_invalid!(message)
      @turn.errors.add(:resolved_config_snapshot, message)
      raise ActiveRecord::RecordInvalid, @turn
    end
  end
end
