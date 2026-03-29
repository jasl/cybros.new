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
      event_summaries_by_node_key = build_event_summaries_by_node_key
      artifact_summaries_by_node_key = build_artifact_summaries_by_node_key
      node_summaries = build_node_summaries(
        node_rows: node_rows,
        node_key_by_id: node_key_by_id,
        workflow_run_summary: workflow_run_summary,
        event_summaries_by_node_key: event_summaries_by_node_key
      )
      edge_summaries = build_edge_summaries(node_key_by_id: node_key_by_id)

      Bundle.new(
        workflow_run: workflow_run_summary,
        nodes: node_summaries.freeze,
        edges: edge_summaries.freeze,
        event_summaries_by_node_key: event_summaries_by_node_key.freeze,
        artifact_summaries_by_node_key: artifact_summaries_by_node_key.freeze,
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
        resume_metadata,
        resolved_model_selection_snapshot = WorkflowRun
        .joins(:conversation, :turn, :workspace)
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
          "workflow_runs.resume_metadata",
          "turns.resolved_model_selection_snapshot"
        )
      provider_handle = resolved_model_selection_snapshot&.fetch("resolved_provider_handle", nil)
      model_ref = resolved_model_selection_snapshot&.fetch("resolved_model_ref", nil)

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
          "resume_metadata" => resume_metadata || {},
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
          :metadata
        )
        .map do |id, public_id, node_key, node_type, ordinal, decision_source, presentation_policy, yielding_workflow_node_id, stage_index, stage_position, metadata|
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
            metadata: metadata || {},
          }
        end
    end

    def build_node_summaries(node_rows:, node_key_by_id:, workflow_run_summary:, event_summaries_by_node_key:)
      successor_node_key = workflow_run_summary.dig("resume_metadata", "successor", "node_key")

      node_rows.map do |row|
        node_key = row.fetch(:node_key)
        events = event_summaries_by_node_key.fetch(node_key, EMPTY_ARRAY)
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
          metadata: deep_freeze(row.fetch(:metadata)),
          state: derive_node_state(events),
          yield_requested: events.any? { |event| event.event_kind == "yield_requested" },
          resume_successor: successor_node_key.present? && successor_node_key == node_key
        ).freeze
      end
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
      WorkflowArtifact
        .where(workflow_run_id: @workflow_run.id)
        .order(:workflow_node_ordinal, :artifact_kind, :artifact_key)
        .pluck(:workflow_node_key, :artifact_key, :artifact_kind, :payload)
        .each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |(workflow_node_key, artifact_key, artifact_kind, payload), grouped|
          grouped[workflow_node_key] << build_artifact_summary(
            artifact_key: artifact_key,
            artifact_kind: artifact_kind,
            payload: payload || {}
          )
        end
        .transform_values { |entries| entries.freeze }
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

    EMPTY_ARRAY = [].freeze
  end
end
