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

      raw_attachment_manifest = build_raw_attachment_manifest
      attachment_manifest = build_attachment_manifest(raw_attachment_manifest)
      {
        "config" => @turn.effective_config_snapshot,
        "execution_context" => {
          "identity" => execution_identity,
          "model_context" => model_context,
          "provider_execution" => provider_execution,
          "budget_hints" => budget_hints,
          "turn_origin" => turn_origin,
          "context_messages" => context_messages,
          "context_imports" => context_imports,
          "attachment_manifest" => attachment_manifest,
          "runtime_attachment_manifest" => build_runtime_attachment_manifest(attachment_manifest),
          "model_input_attachments" => build_model_input_attachments(attachment_manifest),
          "attachment_diagnostics" => build_attachment_diagnostics(raw_attachment_manifest, attachment_manifest),
        },
      }
    end

    private

    def execution_identity
      {
        "user_id" => @turn.conversation.workspace.user.public_id,
        "workspace_id" => @turn.conversation.workspace.public_id,
        "conversation_id" => @turn.conversation.public_id,
        "turn_id" => @turn.public_id,
        "agent_deployment_id" => @turn.agent_deployment.public_id,
      }
    end

    def model_context
      request_context.slice(
        "provider_handle",
        "model_ref",
        "api_model",
        "wire_api",
        "transport",
        "tokenizer_hint",
        "provider_metadata",
        "model_metadata"
      )
    end

    def provider_execution
      {
        "wire_api" => request_context.fetch("wire_api"),
        "execution_settings" => request_context.fetch("execution_settings"),
      }
    end

    def budget_hints
      {
        "hard_limits" => request_context.fetch("hard_limits"),
        "advisory_hints" => request_context.fetch("advisory_hints"),
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
          "message_id" => message.public_id,
          "conversation_id" => message.conversation.public_id,
          "turn_id" => message.turn.public_id,
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
            "kind" => conversation_import.kind,
            "source_conversation_id" => conversation_import.source_conversation&.public_id,
            "source_message_id" => conversation_import.source_message&.public_id,
            "content" => imported_content(conversation_import),
          }.compact
        end
    end

    def build_raw_attachment_manifest
      visible_context_messages.flat_map { |message| message.message_attachments.order(:id).to_a }.map do |attachment|
        {
          "attachment_id" => attachment.public_id,
          "source_message_id" => attachment.message.public_id,
          "origin_attachment_id" => attachment.origin_attachment&.public_id,
          "origin_message_id" => attachment.origin_message&.public_id,
          "filename" => attachment.file.filename.to_s,
          "content_type" => attachment.file.blob.content_type,
          "byte_size" => attachment.file.blob.byte_size,
          "modality" => modality_for(attachment.file.blob.content_type),
          "runtime_ref" => runtime_ref_for(attachment),
        }.compact
      end
    end

    def build_attachment_manifest(raw_attachment_manifest)
      return [] unless @turn.conversation.conversation_attachment_upload?

      raw_attachment_manifest
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

    def build_attachment_diagnostics(raw_attachment_manifest, attachment_manifest)
      unless @turn.conversation.conversation_attachment_upload?
        return raw_attachment_manifest.map do |entry|
          {
            "attachment_id" => entry.fetch("attachment_id"),
            "reason" => "conversation_attachment_upload_disabled",
            "content_type" => entry.fetch("content_type"),
          }
        end
      end

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
        "attachment_id" => attachment.public_id,
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

    def request_context
      @request_context ||= ProviderExecution::BuildRequestContext.call(turn: @turn, catalog: catalog)
    end

    def raise_invalid!(message)
      @turn.errors.add(:resolved_config_snapshot, message)
      raise ActiveRecord::RecordInvalid, @turn
    end
  end
end
