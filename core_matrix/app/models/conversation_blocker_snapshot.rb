class ConversationBlockerSnapshot
  MAINLINE_KEYS = %i[
    active_turn_count
    active_workflow_count
    active_agent_task_count
    open_blocking_interaction_count
    running_subagent_count
  ].freeze

  TAIL_KEYS = %i[
    running_background_process_count
    detached_tool_process_count
    degraded_close_count
  ].freeze

  DEPENDENCY_KEYS = %i[
    descendant_lineage_blockers
    root_lineage_store_blocker
    variable_provenance_blocker
    import_provenance_blocker
  ].freeze

  WORK_BARRIER_KEYS = %i[
    queued_turn_count
    active_turn_count
    active_workflow_count
    queued_agent_task_count
    active_agent_task_count
    open_interaction_count
    open_blocking_interaction_count
    running_process_count
    running_subagent_count
    active_execution_lease_count
  ].freeze

  class WorkBarrier
    def initialize(snapshot)
      @snapshot = snapshot
    end

    WORK_BARRIER_KEYS.each do |key|
      define_method(key) { @snapshot.public_send(key) }
    end

    def [](key)
      to_h[key.to_sym]
    end

    def to_h
      WORK_BARRIER_KEYS.index_with { |key| @snapshot.public_send(key) }
    end
  end

  class DependencyBlockers
    def initialize(snapshot)
      @snapshot = snapshot
    end

    DEPENDENCY_KEYS.each do |key|
      define_method(key) { @snapshot.public_send(key) }
    end

    def blocked?
      @snapshot.dependency_blocked?
    end

    def to_h
      DEPENDENCY_KEYS.index_with { |key| @snapshot.public_send(key) }
    end
  end

  attr_reader :queued_turn_count,
    :active_turn_count,
    :active_workflow_count,
    :queued_agent_task_count,
    :active_agent_task_count,
    :open_interaction_count,
    :open_blocking_interaction_count,
    :running_process_count,
    :running_background_process_count,
    :detached_tool_process_count,
    :running_subagent_count,
    :active_execution_lease_count,
    :degraded_close_count,
    :descendant_lineage_blockers,
    :root_lineage_store_blocker,
    :variable_provenance_blocker,
    :import_provenance_blocker

  def initialize(
    retained:,
    active:,
    closing:,
    queued_turn_count: 0,
    active_turn_count: 0,
    active_workflow_count: 0,
    queued_agent_task_count: 0,
    active_agent_task_count: 0,
    open_interaction_count: 0,
    open_blocking_interaction_count: 0,
    running_process_count: 0,
    running_background_process_count: 0,
    detached_tool_process_count: 0,
    running_subagent_count: 0,
    active_execution_lease_count: 0,
    degraded_close_count: 0,
    descendant_lineage_blockers: 0,
    root_lineage_store_blocker: false,
    variable_provenance_blocker: false,
    import_provenance_blocker: false
  )
    @retained = retained
    @active = active
    @closing = closing
    @queued_turn_count = queued_turn_count
    @active_turn_count = active_turn_count
    @active_workflow_count = active_workflow_count
    @queued_agent_task_count = queued_agent_task_count
    @active_agent_task_count = active_agent_task_count
    @open_interaction_count = open_interaction_count
    @open_blocking_interaction_count = open_blocking_interaction_count
    @running_process_count = running_process_count
    @running_background_process_count = running_background_process_count
    @detached_tool_process_count = detached_tool_process_count
    @running_subagent_count = running_subagent_count
    @active_execution_lease_count = active_execution_lease_count
    @degraded_close_count = degraded_close_count
    @descendant_lineage_blockers = descendant_lineage_blockers
    @root_lineage_store_blocker = root_lineage_store_blocker
    @variable_provenance_blocker = variable_provenance_blocker
    @import_provenance_blocker = import_provenance_blocker
  end

  def retained?
    @retained
  end

  def active?
    @active
  end

  def closing?
    @closing
  end

  def work_barrier
    @work_barrier ||= WorkBarrier.new(self)
  end

  def dependency_blockers
    @dependency_blockers ||= DependencyBlockers.new(self)
  end

  def mainline_clear?
    MAINLINE_KEYS.all? { |key| public_send(key).zero? }
  end

  def tail_pending?
    running_background_process_count.positive? || detached_tool_process_count.positive?
  end

  def tail_degraded?
    degraded_close_count.positive?
  end

  def dependency_blocked?
    descendant_lineage_blockers.positive? ||
      root_lineage_store_blocker ||
      variable_provenance_blocker ||
      import_provenance_blocker
  end

  def live_mutation_block_reason
    return :retained unless retained?
    return :inactive unless active?

    :closing if closing?
  end

  def mutable_for_live_mutation?
    live_mutation_block_reason.nil?
  end

  def close_summary
    {
      mainline: MAINLINE_KEYS.index_with { |key| public_send(key) },
      tail: TAIL_KEYS.index_with { |key| public_send(key) },
      dependencies: dependency_blockers.to_h,
    }
  end

  def to_h
    {
      state: {
        retained: retained?,
        active: active?,
        closing: closing?,
      },
      mainline: close_summary[:mainline],
      tail: close_summary[:tail],
      dependencies: dependency_blockers.to_h,
      work_barrier: work_barrier.to_h,
    }
  end
end
