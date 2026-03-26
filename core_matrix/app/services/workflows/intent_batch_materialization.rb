module Workflows
  class IntentBatchMaterialization
    Result = Struct.new(
      :workflow_run,
      :accepted_nodes,
      :rejected_events,
      :manifest_artifact,
      :barrier_artifacts,
      keyword_init: true
    )

    def self.call(...)
      new(...).call
    end

    def initialize(workflow_run:, yielding_node:, batch_manifest:)
      @workflow_run = workflow_run
      @yielding_node = yielding_node
      @batch_manifest = batch_manifest.deep_stringify_keys
    end

    def call
      ApplicationRecord.transaction do
        accepted_nodes = materialize_accepted_intents!
        rejected_events = materialize_rejected_intents!
        manifest_artifact = persist_manifest_artifact!
        barrier_artifacts = persist_barrier_artifacts!
        persist_yield_event!(accepted_nodes:, rejected_events:, barrier_artifacts:)
        update_resume_metadata!

        Result.new(
          workflow_run: @workflow_run.reload,
          accepted_nodes: accepted_nodes,
          rejected_events: rejected_events,
          manifest_artifact: manifest_artifact,
          barrier_artifacts: barrier_artifacts
        )
      end
    end

    private

    def materialize_accepted_intents!
      nodes = []

      accepted_intents.each do |intent|
        node_attributes = {
          node_key: intent.fetch("node_key"),
          node_type: intent.fetch("node_type"),
          intent_kind: intent.fetch("intent_kind"),
          stage_index: intent.fetch("stage_index"),
          stage_position: intent.fetch("stage_position"),
          yielding_node_key: @yielding_node.node_key,
          presentation_policy: intent.fetch("presentation_policy"),
          decision_source: "agent_program",
          metadata: {
            "batch_id" => batch_id,
            "intent_id" => intent.fetch("intent_id"),
            "intent_kind" => intent.fetch("intent_kind"),
            "requirement" => intent.fetch("requirement"),
            "conflict_scope" => intent["conflict_scope"],
            "payload" => intent.fetch("payload"),
            "idempotency_key" => intent["idempotency_key"],
          },
        }

        Workflows::Mutate.call(
          workflow_run: @workflow_run,
          nodes: [node_attributes],
          edges: [
            {
              from_node_key: @yielding_node.node_key,
              to_node_key: intent.fetch("node_key"),
            },
          ]
        )

        nodes << @workflow_run.workflow_nodes.find_by!(node_key: intent.fetch("node_key"))
      end

      nodes
    end

    def materialize_rejected_intents!
      rejected_intents.each_with_index.map do |intent, index|
        WorkflowNodeEvent.create!(
          installation: @workflow_run.installation,
          workflow_run: @workflow_run,
          workflow_node: @yielding_node,
          ordinal: next_event_ordinal + index,
          event_kind: "intent_rejected",
          payload: {
            "batch_id" => batch_id,
            "intent_id" => intent.fetch("intent_id"),
            "intent_kind" => intent.fetch("intent_kind"),
            "reason" => intent.fetch("rejection_reason"),
            "requirement" => intent.fetch("requirement"),
            "payload" => intent.fetch("payload"),
          }
        )
      end
    end

    def persist_manifest_artifact!
      WorkflowArtifact.create!(
        installation: @workflow_run.installation,
        workflow_run: @workflow_run,
        workflow_node: @yielding_node,
        artifact_key: batch_id,
        artifact_kind: "intent_batch_manifest",
        storage_mode: "inline_json",
        payload: @batch_manifest.merge(
          "accepted_intent_count" => accepted_intents.size,
          "rejected_intent_count" => rejected_intents.size,
        )
      )
    end

    def persist_barrier_artifacts!
      stages
        .select { |stage| stage.fetch("completion_barrier") != "none" }
        .map do |stage|
          WorkflowArtifact.create!(
            installation: @workflow_run.installation,
            workflow_run: @workflow_run,
            workflow_node: @yielding_node,
            artifact_key: "#{batch_id}:stage:#{stage.fetch("stage_index")}",
            artifact_kind: "intent_batch_barrier",
            storage_mode: "inline_json",
            payload: {
              "batch_id" => batch_id,
              "stage" => stage.slice("stage_index", "dispatch_mode", "completion_barrier"),
              "accepted_intent_ids" => stage.fetch("intents").select { |intent| intent.fetch("durable_outcome") == "accepted" }.map { |intent| intent.fetch("intent_id") },
              "rejected_intent_ids" => stage.fetch("intents").select { |intent| intent.fetch("durable_outcome") == "rejected" }.map { |intent| intent.fetch("intent_id") },
            }
          )
        end
    end

    def persist_yield_event!(accepted_nodes:, rejected_events:, barrier_artifacts:)
      WorkflowNodeEvent.create!(
        installation: @workflow_run.installation,
        workflow_run: @workflow_run,
        workflow_node: @yielding_node,
        ordinal: next_event_ordinal + rejected_events.size,
        event_kind: "yield_requested",
        payload: {
          "batch_id" => batch_id,
          "resume_policy" => resume_policy,
          "accepted_node_keys" => accepted_nodes.map(&:node_key),
          "rejected_intent_ids" => rejected_events.map { |event| event.payload.fetch("intent_id") },
          "barrier_artifact_keys" => barrier_artifacts.map(&:artifact_key),
        }
      )
    end

    def update_resume_metadata!
      @workflow_run.update!(
        resume_policy: resume_policy,
        resume_metadata: {
          "batch_id" => batch_id,
          "yielding_node_key" => @yielding_node.node_key,
          "yielding_node_id" => @yielding_node.public_id,
          "successor" => @batch_manifest["successor"],
        }.compact
      )
    end

    def batch_id
      @batch_manifest.fetch("batch_id")
    end

    def resume_policy
      @batch_manifest.fetch("resume_policy")
    end

    def stages
      @stages ||= @batch_manifest.fetch("stages").map do |stage|
        stage.deep_stringify_keys.merge(
          "intents" => Array(stage["intents"]).map.with_index do |intent, index|
            intent.deep_stringify_keys.merge(
              "stage_index" => stage.fetch("stage_index"),
              "stage_position" => index
            )
          end
        )
      end
    end

    def accepted_intents
      @accepted_intents ||= stages.flat_map { |stage| stage.fetch("intents") }.select do |intent|
        intent.fetch("durable_outcome") == "accepted"
      end
    end

    def rejected_intents
      @rejected_intents ||= stages.flat_map { |stage| stage.fetch("intents") }.select do |intent|
        intent.fetch("durable_outcome") == "rejected"
      end
    end

    def next_event_ordinal
      @next_event_ordinal ||= @yielding_node.workflow_node_events.maximum(:ordinal).to_i + 1
    end
  end
end
