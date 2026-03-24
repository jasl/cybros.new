module Subagents
  class Spawn
    def self.call(...)
      new(...).call
    end

    def initialize(workflow_node:, requested_role_or_slot:, parent_subagent_run: nil, batch_key: nil, coordination_key: nil, terminal_summary_artifact: nil, metadata: {})
      @workflow_node = workflow_node
      @requested_role_or_slot = requested_role_or_slot
      @parent_subagent_run = parent_subagent_run
      @batch_key = batch_key
      @coordination_key = coordination_key
      @terminal_summary_artifact = terminal_summary_artifact
      @metadata = metadata
    end

    def call
      SubagentRun.create!(
        installation: @workflow_node.installation,
        workflow_run: @workflow_node.workflow_run,
        workflow_node: @workflow_node,
        parent_subagent_run: @parent_subagent_run,
        lifecycle_state: "running",
        depth: next_depth,
        batch_key: @batch_key,
        coordination_key: @coordination_key,
        requested_role_or_slot: @requested_role_or_slot,
        terminal_summary_artifact: @terminal_summary_artifact,
        metadata: @metadata
      )
    end

    private

    def next_depth
      return 0 if @parent_subagent_run.blank?

      @parent_subagent_run.depth + 1
    end
  end
end
