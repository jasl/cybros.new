require "digest"

module Workflows
  class BuildExecutionSnapshot
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

      capability_snapshot = find_or_create_capability_snapshot!
      context_snapshot = find_or_create_context_snapshot!(attachment_manifest:)
      execution_contract = ExecutionContract.find_or_initialize_by(turn: @turn)

      execution_contract.installation = @turn.installation
      execution_contract.agent_definition_version = @turn.agent_definition_version
      execution_contract.execution_runtime = @turn.execution_runtime
      execution_contract.execution_runtime_version = @turn.execution_runtime_version
      execution_contract.selected_input_message = @turn.selected_input_message
      execution_contract.selected_output_message = @turn.selected_output_message
      if execution_contract.new_record?
        execution_contract.workspace_agent_global_instructions_document = workspace_agent_global_instructions_document
        execution_contract.workspace_agent_profile_settings_document = workspace_agent_profile_settings_document
      end
      execution_contract.execution_capability_snapshot = capability_snapshot
      execution_contract.execution_context_snapshot = context_snapshot
      execution_contract.provider_context = provider_context
      execution_contract.turn_origin = turn_origin
      execution_contract.attachment_manifest = attachment_manifest
      execution_contract.model_input_attachments = build_model_input_attachments(attachment_manifest)
      execution_contract.attachment_diagnostics = build_attachment_diagnostics(raw_attachment_manifest, attachment_manifest)
      execution_contract.save!

      unless @turn.execution_contract_id == execution_contract.id
        @turn.update!(execution_contract: execution_contract)
      end
      @turn.execution_contract = execution_contract

      TurnExecutionSnapshot.new(turn: @turn)
    end

    private

    def find_or_create_capability_snapshot!
      tool_surface_document = JsonDocuments::Store.call(
        installation: @turn.installation,
        document_kind: "execution_tool_surface",
        payload: visible_tool_surface
      )

      snapshot_payload = {
        "tool_surface_sha" => tool_surface_document.content_sha256,
        "agent_definition_fingerprint" => @turn.agent_definition_version.fingerprint,
        "profile_key" => current_profile_key,
        "model_selector_hint" => subagent_connection&.resolved_model_selector_hint,
        "subagent" => subagent_connection.present?,
        "subagent_connection_id" => subagent_connection&.public_id,
        "parent_subagent_connection_id" => subagent_connection&.parent_subagent_connection&.public_id,
        "subagent_depth" => subagent_connection&.depth,
        "owner_conversation_id" => subagent_connection&.owner_conversation&.public_id,
        "subagent_policy" => deep_stringify(capability_contract.default_canonical_config.fetch("subagents", {})),
      }
      fingerprint = "sha256:#{Digest::SHA256.hexdigest(JSON.generate(snapshot_payload))}"

      ExecutionCapabilitySnapshot.find_or_create_by!(
        installation: @turn.installation,
        fingerprint: fingerprint
      ) do |snapshot|
        snapshot.tool_surface_document = tool_surface_document
        snapshot.agent_definition_version = @turn.agent_definition_version
        snapshot.profile_key = current_profile_key
        snapshot.model_selector_hint = snapshot_payload.fetch("model_selector_hint")
        snapshot.subagent = subagent_connection.present?
        snapshot.subagent_connection = subagent_connection
        snapshot.parent_subagent_connection = subagent_connection&.parent_subagent_connection
        snapshot.owner_conversation = subagent_connection&.owner_conversation
        snapshot.subagent_depth = subagent_connection&.depth
        snapshot.subagent_policy_snapshot = snapshot_payload.fetch("subagent_policy")
      end
    end

    def find_or_create_context_snapshot!(attachment_manifest:)
      message_refs = build_message_refs
      import_refs = build_import_refs
      attachment_refs = build_attachment_refs(attachment_manifest)
      projection_fingerprint = projection_fingerprint(message_refs:, import_refs:)
      fingerprint = "sha256:#{Digest::SHA256.hexdigest(JSON.generate({ "messages" => message_refs, "imports" => import_refs, "attachments" => attachment_refs }))}"

      ExecutionContextSnapshot.find_or_create_by!(
        installation: @turn.installation,
        fingerprint: fingerprint
      ) do |snapshot|
        snapshot.projection_fingerprint = projection_fingerprint
        snapshot.message_refs = message_refs
        snapshot.import_refs = import_refs
        snapshot.attachment_refs = attachment_refs
      end
    end

    def provider_context
      {
        "budget_hints" => budget_hints,
        "provider_execution" => provider_execution,
        "model_context" => model_context,
        "feature_policies" => feature_policies,
        "request_preparation" => request_preparation,
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

    def model_context
      {
        "provider_handle" => @turn.resolved_provider_handle,
        "model_ref" => @turn.resolved_model_ref,
        "api_model" => model_definition.fetch(:api_model),
        "wire_api" => provider_definition.fetch(:wire_api),
        "transport" => provider_definition.fetch(:transport),
        "tokenizer_hint" => model_definition.fetch(:tokenizer_hint),
        "capabilities" => deep_stringify(model_definition.fetch(:capabilities, {})),
        "provider_metadata" => deep_stringify(provider_definition.fetch(:metadata, {})),
        "model_metadata" => deep_stringify(model_definition.fetch(:metadata, {})),
      }
    end

    def provider_execution
      {
        "wire_api" => provider_definition.fetch(:wire_api),
        "execution_settings" => execution_settings,
        "loop_policy" => provider_loop_policy,
      }
    end

    def feature_policies
      {
        "prompt_compaction" => ProviderExecution::PromptCompactionPolicy.call(
          workspace: @turn.conversation.workspace,
          agent_definition_version: @turn.agent_definition_version
        ),
      }
    end

    def request_preparation
      prompt_compaction_policy = ProviderExecution::PromptCompactionPolicy.call(
        workspace: @turn.conversation.workspace,
        agent_definition_version: @turn.agent_definition_version
      )

      {
        "prompt_compaction" => {
          "policy" => prompt_compaction_policy,
          "capability" => ProviderExecution::RequestPreparationCapabilityResolver.call(
            agent_definition_version: @turn.agent_definition_version
          ).fetch("prompt_compaction"),
        },
      }
    end

    def budget_hints
      advisory = ProviderExecution::PromptBudgetAdvisory.call(
        provider_handle: @turn.resolved_provider_handle,
        model_ref: @turn.resolved_model_ref,
        api_model: model_definition.fetch(:api_model),
        tokenizer_hint: model_definition.fetch(:tokenizer_hint),
        context_window_tokens: model_definition.fetch(:context_window_tokens),
        max_output_tokens: model_definition.fetch(:max_output_tokens),
        context_soft_limit_ratio: model_definition.fetch(:context_soft_limit_ratio)
      )

      {
        "hard_limits" => {
          "context_window_tokens" => model_definition.fetch(:context_window_tokens),
          "max_output_tokens" => model_definition.fetch(:max_output_tokens),
          "hard_input_token_limit" => advisory.fetch("hard_input_token_limit"),
        },
        "advisory_hints" => {
          "recommended_input_tokens" => advisory.fetch("recommended_input_tokens"),
          "recommended_compaction_threshold" => advisory.fetch("recommended_compaction_threshold"),
          "soft_threshold_tokens" => advisory.fetch("soft_threshold_tokens"),
          "reserved_tokens" => advisory.fetch("reserved_tokens"),
          "reserved_output_tokens" => advisory.fetch("reserved_output_tokens"),
          "context_soft_limit_ratio" => model_definition.fetch(:context_soft_limit_ratio),
        },
      }
    end

    def build_message_refs
      visible_context_messages.filter_map do |message|
        next unless message.is_a?(Message)

        {
          "message_id" => message.public_id,
          "role" => provider_role_for(message),
          "slot" => message.slot,
          "created_at" => message.created_at&.iso8601,
        }
      end
    end

    def build_import_refs
      @turn.conversation.conversation_imports
        .includes(:source_conversation, :source_message, :summary_segment)
        .order(:id)
        .filter_map do |conversation_import|
          next if conversation_import.summary_segment&.superseded_by_id.present?

          {
            "kind" => conversation_import.kind,
            "source_conversation_id" => conversation_import.source_conversation&.public_id,
            "source_message_id" => conversation_import.source_message&.public_id,
            "summary_segment_id" => conversation_import.summary_segment_id,
          }.compact
        end
    end

    def build_attachment_refs(attachment_manifest)
      attachment_manifest.map do |entry|
        entry.slice(
          "attachment_id",
          "source_message_id",
          "origin_attachment_id",
          "origin_message_id",
          "filename",
          "content_type",
          "byte_size",
          "publication_role",
          "source_kind",
          "modality"
        )
      end
    end

    def projection_fingerprint(message_refs:, import_refs:)
      payload = {
        "messages" => message_refs,
        "context_imports" => import_refs,
      }

      "sha256:#{Digest::SHA256.hexdigest(JSON.generate(payload))}"
    end

    def workspace_agent_global_instructions_document
      global_instructions = @turn.conversation.workspace_agent&.global_instructions
      return if global_instructions.blank?

      JsonDocuments::Store.call(
        installation: @turn.installation,
        document_kind: "workspace_agent_global_instructions",
        payload: { "global_instructions" => global_instructions }
      )
    end

    def workspace_agent_profile_settings_document
      profile_settings = @turn.conversation.workspace_agent&.profile_settings_view
      return if profile_settings.blank?

      JsonDocuments::Store.call(
        installation: @turn.installation,
        document_kind: "workspace_agent_profile_settings",
        payload: { "profile_settings" => profile_settings }
      )
    end

    def provider_role_for(message)
      case message.role
      when "agent"
        "assistant"
      else
        message.role
      end
    end

    def visible_tool_surface
      capability_surface.fetch("tool_catalog", []).map { |entry| deep_stringify(entry) }
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
          "publication_role" => Attachments::CreateForMessage.publication_role_for(attachment),
          "source_kind" => Attachments::CreateForMessage.source_kind_for(attachment),
          "modality" => modality_for(attachment.file.blob.content_type),
        }.compact
      end
    end

    def build_attachment_manifest(raw_attachment_manifest)
      raw_attachment_manifest
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

    def build_attachment_diagnostics(_raw_attachment_manifest, attachment_manifest)
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
      @visible_context_messages ||= Conversations::ContextProjection.call(conversation: @turn.conversation).messages.select do |message|
        message.conversation_id != @turn.conversation_id || message.turn.sequence <= @turn.sequence
      end
    end

    def modality_for(content_type)
      return "image" if content_type.start_with?("image/")
      return "audio" if content_type.start_with?("audio/")
      return "video" if content_type.start_with?("video/")

      "file"
    end

    def modality_supported?(modality)
      effective_catalog.model(@turn.resolved_provider_handle, @turn.resolved_model_ref)
        .dig(:capabilities, :multimodal_inputs, modality.to_sym) == true
    end

    def effective_catalog
      @effective_catalog ||= ProviderCatalog::EffectiveCatalog.new(installation: @turn.installation)
    end

    def provider_definition
      @provider_definition ||= effective_catalog.provider(@turn.resolved_provider_handle)
    end

    def model_definition
      @model_definition ||= effective_catalog.model(@turn.resolved_provider_handle, @turn.resolved_model_ref)
    end

    def execution_settings
      ProviderRequestSettingsSchema
        .for(provider_definition.fetch(:wire_api))
        .merge_execution_settings(
          request_defaults: model_definition.fetch(:request_defaults, {}),
          runtime_overrides: @turn.resolved_config_snapshot
        )
    rescue ProviderRequestSettingsSchema::InvalidSettings => error
      raise_invalid!(error.message)
    end

    def provider_loop_policy
      ProviderLoopPolicy.build(runtime_overrides: @turn.resolved_config_snapshot)
    rescue ProviderLoopPolicy::InvalidPolicy => error
      raise_invalid!(error.message)
    end

    def deep_stringify(value)
      case value
      when Hash
        value.each_with_object({}) do |(key, nested_value), out|
          out[key.to_s] = deep_stringify(nested_value)
        end
      when Array
        value.map { |item| deep_stringify(item) }
      else
        value
      end
    end

    def raise_invalid!(message)
      @turn.errors.add(:resolved_config_snapshot, message)
      raise ActiveRecord::RecordInvalid, @turn
    end

    def capability_surface
      @capability_surface ||= RuntimeCapabilities::ComposeForTurn.call(turn: @turn)
    end

    def capability_contract
      @capability_contract ||= RuntimeCapabilities::ComposeForTurn.new(turn: @turn).contract
    end

    def subagent_connection
      @subagent_connection ||= @turn.conversation.subagent_connection
    end

    def current_profile_key
      RuntimeCapabilities::ComposeForTurn.new(turn: @turn).current_profile_key
    end
  end
end
