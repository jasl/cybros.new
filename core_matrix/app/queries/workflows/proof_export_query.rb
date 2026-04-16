module Workflows
  class ProofExportQuery
    Bundle = Struct.new(
      :workflow_run,
      :nodes,
      :edges,
      :event_summaries_by_node_key,
      :artifact_summaries_by_node_key,
      :observed_dag_shape,
      keyword_init: true
    )

    NodeSummary = Struct.new(
      :public_id,
      :node_key,
      :node_type,
      :ordinal,
      :decision_source,
      :presentation_policy,
      :yielding_node_key,
      :stage_index,
      :stage_position,
      :metadata,
      :state,
      :yield_requested,
      :resume_successor,
      keyword_init: true
    )

    EdgeSummary = Struct.new(
      :from_node_key,
      :to_node_key,
      :ordinal,
      keyword_init: true
    )

    EventSummary = Struct.new(
      :event_kind,
      :ordinal,
      :summary_text,
      :state,
      :batch_id,
      :accepted_node_keys,
      :barrier_artifact_keys,
      :reason,
      keyword_init: true
    )

    ArtifactSummary = Struct.new(
      :artifact_key,
      :artifact_kind,
      :summary_text,
      :barrier_kind,
      :stage_index,
      :dispatch_mode,
      keyword_init: true
    )

    def self.call(...)
      new(...).call
    end

    def initialize(workflow_run:)
      @workflow_run = workflow_run
    end

    def call
      workflow_run_summary = load_workflow_run_summary
      node_rows = load_node_rows
      node_key_by_id = node_rows.to_h { |row| [row.fetch(:id), row.fetch(:node_key)] }
      tool_call_payloads_by_document_id = load_tool_call_payloads(node_rows)
      event_summaries_by_node_key = build_event_summaries_by_node_key
      artifact_result = build_artifact_summaries_by_node_key
      node_summaries = build_node_summaries(
        node_rows: node_rows,
        node_key_by_id: node_key_by_id,
        workflow_run_summary: workflow_run_summary,
        event_summaries_by_node_key: event_summaries_by_node_key,
        tool_call_payloads_by_document_id: tool_call_payloads_by_document_id,
        manifest_payloads_by_yield_node_and_batch_id: artifact_result.fetch(:manifest_payloads_by_yield_node_and_batch_id)
      )
      edge_summaries = build_edge_summaries(node_key_by_id: node_key_by_id)

      Bundle.new(
        workflow_run: workflow_run_summary,
        nodes: node_summaries.freeze,
        edges: edge_summaries.freeze,
        event_summaries_by_node_key: event_summaries_by_node_key.freeze,
        artifact_summaries_by_node_key: artifact_result.fetch(:artifact_summaries_by_node_key).freeze,
        observed_dag_shape: edge_summaries.map { |edge| "#{edge.from_node_key}->#{edge.to_node_key}" }.freeze
      ).freeze
    end

    private

    def load_workflow_run_summary
      public_id,
        conversation_public_id,
        turn_public_id,
        workspace_public_id,
        conversation_state,
        turn_lifecycle_state,
        workflow_lifecycle_state,
        workflow_wait_state,
        wait_reason_kind,
        resume_policy,
        resume_batch_id,
        resume_yielding_node_key,
        resume_successor_node_key,
        resume_successor_node_type,
        resolved_model_selection_snapshot = WorkflowRun
        .joins(:turn)
        .joins(conversation: :workspace)
        .where(id: @workflow_run.id)
        .pick(
          "workflow_runs.public_id",
          "conversations.public_id",
          "turns.public_id",
          "workspaces.public_id",
          "conversations.lifecycle_state",
          "turns.lifecycle_state",
          "workflow_runs.lifecycle_state",
          "workflow_runs.wait_state",
          "workflow_runs.wait_reason_kind",
          "workflow_runs.resume_policy",
          "workflow_runs.resume_batch_id",
          "workflow_runs.resume_yielding_node_key",
          "workflow_runs.resume_successor_node_key",
          "workflow_runs.resume_successor_node_type",
          "turns.resolved_model_selection_snapshot"
        )
      provider_handle = resolved_model_selection_snapshot&.fetch("resolved_provider_handle", nil)
      model_ref = resolved_model_selection_snapshot&.fetch("resolved_model_ref", nil)
      successor = {
        "node_key" => resume_successor_node_key,
        "node_type" => resume_successor_node_type,
      }.compact

      deep_freeze(
        {
          "public_id" => public_id,
          "conversation_id" => conversation_public_id,
          "turn_id" => turn_public_id,
          "workspace_id" => workspace_public_id,
          "conversation_state" => conversation_state,
          "turn_lifecycle_state" => turn_lifecycle_state,
          "workflow_lifecycle_state" => workflow_lifecycle_state,
          "workflow_wait_state" => workflow_wait_state,
          "wait_reason_kind" => wait_reason_kind,
          "resume_policy" => resume_policy,
          "resume_metadata" => {
            "batch_id" => resume_batch_id,
            "yielding_node_key" => resume_yielding_node_key,
            "successor" => successor.presence,
          }.compact,
          "provider_handle" => provider_handle,
          "model_ref" => model_ref,
        }
      )
    end

    def load_node_rows
      WorkflowNode
        .where(workflow_run_id: @workflow_run.id)
        .order(:ordinal)
        .pluck(
          :id,
          :public_id,
          :node_key,
          :node_type,
          :ordinal,
          :decision_source,
          :presentation_policy,
          :yielding_workflow_node_id,
          :stage_index,
          :stage_position,
          :intent_id,
          :intent_batch_id,
          :intent_requirement,
          :intent_conflict_scope,
          :intent_idempotency_key,
          :provider_round_index,
          :prior_tool_node_keys,
          :blocked_retry_failure_kind,
          :blocked_retry_attempt_no,
          :transcript_side_effect_committed,
          :tool_call_document_id,
          :metadata,
          :spawned_subagent_connection_id
        )
        .map do |id, public_id, node_key, node_type, ordinal, decision_source, presentation_policy, yielding_workflow_node_id, stage_index, stage_position, intent_id, intent_batch_id, intent_requirement, intent_conflict_scope, intent_idempotency_key, provider_round_index, prior_tool_node_keys, blocked_retry_failure_kind, blocked_retry_attempt_no, transcript_side_effect_committed, tool_call_document_id, metadata, spawned_subagent_connection_id|
          {
            id: id,
            public_id: public_id,
            node_key: node_key,
            node_type: node_type,
            ordinal: ordinal,
            decision_source: decision_source,
            presentation_policy: presentation_policy,
            yielding_workflow_node_id: yielding_workflow_node_id,
            stage_index: stage_index,
            stage_position: stage_position,
            intent_id: intent_id,
            intent_batch_id: intent_batch_id,
            intent_requirement: intent_requirement,
            intent_conflict_scope: intent_conflict_scope,
            intent_idempotency_key: intent_idempotency_key,
            provider_round_index: provider_round_index,
            prior_tool_node_keys: prior_tool_node_keys,
            blocked_retry_failure_kind: blocked_retry_failure_kind,
            blocked_retry_attempt_no: blocked_retry_attempt_no,
            transcript_side_effect_committed: transcript_side_effect_committed,
            tool_call_document_id: tool_call_document_id,
            metadata: metadata || {},
            spawned_subagent_connection_id: spawned_subagent_connection_id,
          }
        end
    end

    def load_tool_call_payloads(node_rows)
      document_ids = node_rows.map { |row| row[:tool_call_document_id] }.compact
      return {} if document_ids.empty?

      JsonDocument.where(id: document_ids).pluck(:id, :payload).to_h
    end

    def load_spawned_subagent_payloads(node_rows)
      session_ids = node_rows.map { |row| row[:spawned_subagent_connection_id] }.compact
      return {} if session_ids.empty?

      SubagentConnection
        .where(id: session_ids)
        .pluck(:id, :public_id, :profile_key, :resolved_model_selector_hint)
        .each_with_object({}) do |(id, public_id, profile_key, resolved_model_selector_hint), out|
          out[id] = {
            "subagent_connection_id" => public_id,
            "profile_key" => profile_key,
            "specialist_key" => specialist_key_for(profile_key),
            "profile_group" => profile_group_for(profile_key),
            "resolved_model_selector_hint" => resolved_model_selector_hint.presence,
          }.compact.freeze
        end
    end

    def build_node_summaries(node_rows:, node_key_by_id:, workflow_run_summary:, event_summaries_by_node_key:, tool_call_payloads_by_document_id:, manifest_payloads_by_yield_node_and_batch_id:)
      successor_node_key = workflow_run_summary.dig("resume_metadata", "successor", "node_key")
      spawned_subagent_payloads = load_spawned_subagent_payloads(node_rows)

      node_rows.map do |row|
        node_key = row.fetch(:node_key)
        events = event_summaries_by_node_key.fetch(node_key, EMPTY_ARRAY)
        metadata = row.fetch(:metadata).dup
        tool_call_payload = tool_call_payloads_by_document_id[row[:tool_call_document_id]]
        metadata["tool_call"] = tool_call_payload if tool_call_payload.present?
        metadata["spawned_subagent"] = spawned_subagent_payloads[row[:spawned_subagent_connection_id]] if row[:spawned_subagent_connection_id].present?
        intent = build_intent_metadata(row, manifest_payloads_by_yield_node_and_batch_id)
        metadata["intent"] = intent if intent.present?
        metadata["provider_round_index"] = row[:provider_round_index] if row[:provider_round_index].present?
        metadata["prior_tool_node_keys"] = row[:prior_tool_node_keys] if Array(row[:prior_tool_node_keys]).any?
        if row[:blocked_retry_failure_kind].present? && row[:blocked_retry_attempt_no].present?
          metadata["blocked_retry_state"] = {
            "failure_kind" => row[:blocked_retry_failure_kind],
            "attempt_no" => row[:blocked_retry_attempt_no],
          }
        end
        metadata["transcript_side_effect_committed"] = true if row[:transcript_side_effect_committed]
        NodeSummary.new(
          public_id: row.fetch(:public_id),
          node_key: node_key,
          node_type: row.fetch(:node_type),
          ordinal: row.fetch(:ordinal),
          decision_source: row.fetch(:decision_source),
          presentation_policy: row.fetch(:presentation_policy),
          yielding_node_key: node_key_by_id[row.fetch(:yielding_workflow_node_id)],
          stage_index: row.fetch(:stage_index),
          stage_position: row.fetch(:stage_position),
          metadata: deep_freeze(metadata),
          state: derive_node_state(events),
          yield_requested: events.any? { |event| event.event_kind == "yield_requested" },
          resume_successor: successor_node_key.present? && successor_node_key == node_key
        ).freeze
      end
    end

    def build_intent_metadata(row, manifest_payloads_by_yield_node_and_batch_id)
      return if row[:intent_id].blank? && row[:intent_batch_id].blank?

      payload = resolve_intent_payload(row, manifest_payloads_by_yield_node_and_batch_id)
      {
        "intent_id" => row[:intent_id],
        "batch_id" => row[:intent_batch_id],
        "requirement" => row[:intent_requirement],
        "conflict_scope" => row[:intent_conflict_scope],
        "idempotency_key" => row[:intent_idempotency_key],
        "payload" => payload.presence,
      }.compact
    end

    def resolve_intent_payload(row, manifest_payloads_by_yield_node_and_batch_id)
      manifest_payload = manifest_payloads_by_yield_node_and_batch_id[[row[:yielding_workflow_node_id], row[:intent_batch_id]]] || {}

      Array(manifest_payload["stages"])
        .flat_map { |stage| Array(stage["intents"]) }
        .find { |intent| intent["intent_id"] == row[:intent_id] }
        &.fetch("payload", {}) || {}
    end

    def build_edge_summaries(node_key_by_id:)
      WorkflowEdge
        .where(workflow_run_id: @workflow_run.id)
        .order(:from_node_id, :ordinal)
        .pluck(:from_node_id, :to_node_id, :ordinal)
        .map do |from_node_id, to_node_id, ordinal|
          EdgeSummary.new(
            from_node_key: node_key_by_id.fetch(from_node_id),
            to_node_key: node_key_by_id.fetch(to_node_id),
            ordinal: ordinal
          ).freeze
        end
    end

    def build_event_summaries_by_node_key
      WorkflowNodeEvent
        .where(workflow_run_id: @workflow_run.id)
        .order(:workflow_node_ordinal, :ordinal)
        .pluck(:workflow_node_key, :event_kind, :ordinal, :payload)
        .each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |(workflow_node_key, event_kind, ordinal, payload), grouped|
          grouped[workflow_node_key] << build_event_summary(
            event_kind: event_kind,
            ordinal: ordinal,
            payload: payload || {}
          )
        end
        .transform_values { |entries| entries.freeze }
    end

    def build_event_summary(event_kind:, ordinal:, payload:)
      case event_kind
      when "status"
        EventSummary.new(
          event_kind: event_kind,
          ordinal: ordinal,
          state: payload["state"],
          summary_text: "state: #{payload["state"]}"
        ).freeze
      when "yield_requested"
        EventSummary.new(
          event_kind: event_kind,
          ordinal: ordinal,
          batch_id: payload["batch_id"],
          accepted_node_keys: Array(payload["accepted_node_keys"]).freeze,
          barrier_artifact_keys: Array(payload["barrier_artifact_keys"]).freeze,
          summary_text: "yield batch: #{payload["batch_id"]}"
        ).freeze
      when "intent_rejected"
        EventSummary.new(
          event_kind: event_kind,
          ordinal: ordinal,
          reason: payload["reason"],
          summary_text: "intent rejected: #{payload["reason"]}"
        ).freeze
      else
        EventSummary.new(
          event_kind: event_kind,
          ordinal: ordinal,
          summary_text: event_kind.to_s
        ).freeze
      end
    end

    def build_artifact_summaries_by_node_key
      summaries_by_node_key = Hash.new { |hash, key| hash[key] = [] }
      manifest_payloads_by_yield_node_and_batch_id = {}

      WorkflowArtifact
        .where(workflow_run_id: @workflow_run.id)
        .order(:workflow_node_ordinal, :artifact_kind, :artifact_key)
        .left_outer_joins(:json_document)
        .pluck(:workflow_node_id, :workflow_node_key, :artifact_key, :artifact_kind, Arel.sql("json_documents.payload"))
        .each do |workflow_node_id, workflow_node_key, artifact_key, artifact_kind, payload|
          payload ||= {}
          summaries_by_node_key[workflow_node_key] << build_artifact_summary(
            artifact_key: artifact_key,
            artifact_kind: artifact_kind,
            payload: payload
          )
          if artifact_kind == "intent_batch_manifest"
            manifest_payloads_by_yield_node_and_batch_id[[workflow_node_id, artifact_key]] = payload
          end
        end

      {
        artifact_summaries_by_node_key: summaries_by_node_key.transform_values(&:freeze),
        manifest_payloads_by_yield_node_and_batch_id: manifest_payloads_by_yield_node_and_batch_id.freeze,
      }
    end

    def build_artifact_summary(artifact_key:, artifact_kind:, payload:)
      if artifact_kind == "intent_batch_barrier"
        stage = payload.fetch("stage", {})

        return ArtifactSummary.new(
          artifact_key: artifact_key,
          artifact_kind: artifact_kind,
          barrier_kind: stage["completion_barrier"],
          stage_index: stage["stage_index"],
          dispatch_mode: stage["dispatch_mode"],
          summary_text: "barrier: #{stage["completion_barrier"]}"
        ).freeze
      end

      ArtifactSummary.new(
        artifact_key: artifact_key,
        artifact_kind: artifact_kind,
        summary_text: artifact_kind.to_s
      ).freeze
    end

    def derive_node_state(events)
      return "yielded" if events.any? { |event| event.event_kind == "yield_requested" }

      events.reverse_each do |event|
        return event.state if event.state.present?
      end

      "pending"
    end

    def deep_freeze(value)
      case value
      when Hash
        value.each_with_object({}) do |(key, nested_value), frozen_hash|
          frozen_hash[key] = deep_freeze(nested_value)
        end.freeze
      when Array
        value.map { |entry| deep_freeze(entry) }.freeze
      else
        value.frozen? ? value : value.freeze
      end
    end

    def specialist_key_for(profile_key)
      profile_key.to_s.strip.presence
    end

    def profile_group_for(profile_key)
      return if specialist_key_for(profile_key).blank?

      "specialist"
    end

    EMPTY_ARRAY = [].freeze
  end
end
