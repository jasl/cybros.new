module Workflows
  class Mutate
    def self.call(...)
      new(...).call
    end

    def initialize(workflow_run:, nodes: [], edges: [])
      @workflow_run = workflow_run
      @nodes = Array(nodes)
      @edges = Array(edges)
    end

    def call
      ApplicationRecord.transaction do
        @workflow_run.with_lock do
          node_lookup = workflow_nodes_scope.index_by(&:node_key)
          append_nodes!(node_lookup)
          append_edges!(node_lookup)
          validate_acyclic!
          @workflow_run
        end
      end
    end

    private

    def append_nodes!(node_lookup)
      next_ordinal = workflow_nodes_scope.maximum(:ordinal).to_i + 1

      @nodes.each do |node_attributes|
        yielding_node = resolve_optional_node(node_lookup, node_attributes[:yielding_node_key])
        tool_call_document = resolve_tool_call_document(node_attributes)
        node = WorkflowNode.create!(
          installation: @workflow_run.installation,
          workflow_run: @workflow_run,
          ordinal: next_ordinal,
          node_key: node_attributes.fetch(:node_key),
          node_type: node_attributes.fetch(:node_type),
          lifecycle_state: node_attributes.fetch(:lifecycle_state, "pending"),
          intent_kind: node_attributes[:intent_kind],
          intent_id: node_attributes[:intent_id],
          intent_batch_id: node_attributes[:intent_batch_id],
          intent_requirement: node_attributes[:intent_requirement],
          intent_conflict_scope: node_attributes[:intent_conflict_scope],
          intent_idempotency_key: node_attributes[:intent_idempotency_key],
          opened_human_interaction_request: node_attributes[:opened_human_interaction_request],
          spawned_subagent_connection: node_attributes[:spawned_subagent_connection],
          provider_round_index: node_attributes[:provider_round_index],
          prior_tool_node_keys: node_attributes.fetch(:prior_tool_node_keys, []),
          blocked_retry_failure_kind: node_attributes[:blocked_retry_failure_kind],
          blocked_retry_attempt_no: node_attributes[:blocked_retry_attempt_no],
          transcript_side_effect_committed: node_attributes.fetch(:transcript_side_effect_committed, false),
          stage_index: node_attributes[:stage_index],
          stage_position: node_attributes[:stage_position],
          yielding_workflow_node: yielding_node,
          tool_call_document: tool_call_document,
          presentation_policy: node_attributes.fetch(:presentation_policy, "internal_only"),
          decision_source: node_attributes.fetch(:decision_source),
          metadata: node_attributes.fetch(:metadata, {})
        )
        node_lookup[node.node_key] = node
        next_ordinal += 1
      end
    end

    def resolve_tool_call_document(node_attributes)
      return node_attributes[:tool_call_document] if node_attributes[:tool_call_document].present?

      payload = node_attributes[:tool_call_payload]
      return if payload.blank?

      JsonDocuments::Store.call(
        installation: @workflow_run.installation,
        document_kind: "workflow_node_tool_call",
        payload: payload
      )
    end

    def append_edges!(node_lookup)
      grouped_ordinals = Hash.new do |hash, node_id|
        existing_maximum = workflow_edges_scope.where(from_node_id: node_id).maximum(:ordinal)
        hash[node_id] = existing_maximum.nil? ? 0 : existing_maximum + 1
      end

      @edges.each do |edge_attributes|
        from_node = resolve_node!(node_lookup, edge_attributes.fetch(:from_node_key))
        to_node = resolve_node!(node_lookup, edge_attributes.fetch(:to_node_key))

        WorkflowEdge.create!(
          installation: @workflow_run.installation,
          workflow_run: @workflow_run,
          from_node: from_node,
          to_node: to_node,
          requirement: edge_attributes.fetch(:requirement, "required"),
          ordinal: grouped_ordinals[from_node.id]
        )
        grouped_ordinals[from_node.id] += 1
      end
    end

    def validate_acyclic!
      adjacency = Hash.new { |hash, key| hash[key] = [] }

      workflow_edges_scope.find_each do |edge|
        adjacency[edge.from_node_id] << edge.to_node_id
      end

      visited = {}
      visiting = {}

      workflow_nodes_scope.pluck(:id).each do |node_id|
        next if visited[node_id]
        next unless cycle_from?(node_id, adjacency, visited, visiting)

        raise_invalid!(@workflow_run, :base, "must remain acyclic after mutation")
      end
    end

    def cycle_from?(node_id, adjacency, visited, visiting)
      return true if visiting[node_id]
      return false if visited[node_id]

      visiting[node_id] = true

      adjacency[node_id].each do |child_id|
        return true if cycle_from?(child_id, adjacency, visited, visiting)
      end

      visiting.delete(node_id)
      visited[node_id] = true
      false
    end

    def raise_invalid!(record, attribute, message)
      record.errors.add(attribute, message)
      raise ActiveRecord::RecordInvalid, record
    end

    def resolve_node!(node_lookup, node_key)
      node_lookup.fetch(node_key)
    rescue KeyError
      raise_invalid!(@workflow_run, :base, "references unknown workflow node key #{node_key}")
    end

    def resolve_optional_node(node_lookup, node_key)
      return if node_key.blank?

      resolve_node!(node_lookup, node_key)
    end

    def workflow_nodes_scope
      WorkflowNode.where(workflow_run: @workflow_run)
    end

    def workflow_edges_scope
      WorkflowEdge.where(workflow_run: @workflow_run)
    end
  end
end
