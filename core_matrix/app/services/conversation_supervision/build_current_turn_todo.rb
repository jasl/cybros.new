require "digest/md5"

module ConversationSupervision
  class BuildCurrentTurnTodo
    ACTIVE_TASK_LIFECYCLE_STATES = %w[queued running].freeze
    ACTIVE_WORKFLOW_NODE_STATES = %w[running waiting].freeze
    FEED_EVENT_KIND_BY_STATUS = {
      "completed" => "turn_todo_item_completed",
      "blocked" => "turn_todo_item_blocked",
      "canceled" => "turn_todo_item_canceled",
      "failed" => "turn_todo_item_failed",
      "in_progress" => "turn_todo_item_started",
    }.freeze

    def self.call(...)
      new(...).call
    end

    def initialize(conversation:, active_agent_task_run: nil, workflow_run: nil)
      @conversation = conversation
      @active_agent_task_run = active_agent_task_run if active_agent_task_run.present?
      @workflow_run = workflow_run if workflow_run.present?
    end

    def call
      return persisted_projection if persisted_projection?
      return empty_projection if relevant_nodes.empty?

      {
        "plan_view" => workflow_plan_view,
        "plan_summary" => workflow_plan_summary,
        "synthetic_turn_feed" => synthetic_turn_feed,
      }
    end

    private

    def persisted_projection?
      active_agent_task_run&.turn_todo_plan.present?
    end

    def persisted_projection
      {
        "plan_view" => TurnTodoPlans::BuildView.call(turn_todo_plan: active_agent_task_run.turn_todo_plan),
        "plan_summary" => TurnTodoPlans::BuildCompactView.call(turn_todo_plan: active_agent_task_run.turn_todo_plan),
        "synthetic_turn_feed" => [],
      }
    end

    def empty_projection
      {
        "plan_view" => nil,
        "plan_summary" => nil,
        "synthetic_turn_feed" => [],
      }
    end

    def workflow_plan_view
      @workflow_plan_view ||= begin
        items = plan_items
        current_item = items.find { |item| item.fetch("item_key") == current_item_key }

        {
          "turn_todo_plan_id" => stable_public_id("workflow-turn-todo-plan", @conversation.public_id, feed_turn.public_id),
          "conversation_id" => @conversation.public_id,
          "turn_id" => feed_turn.public_id,
          "status" => workflow_plan_status,
          "goal_summary" => goal_summary,
          "current_item_key" => current_item_key,
          "current_item" => current_item,
          "counts" => TurnTodoPlans::BuildCounts.call(items: items).deep_stringify_keys,
          "items" => items,
        }.compact
      end
    end

    def workflow_plan_summary
      @workflow_plan_summary ||= begin
        plan_view = workflow_plan_view
        counts = plan_view.fetch("counts", {})

        {
          "turn_todo_plan_id" => plan_view.fetch("turn_todo_plan_id"),
          "conversation_id" => plan_view.fetch("conversation_id"),
          "turn_id" => plan_view.fetch("turn_id"),
          "status" => plan_view.fetch("status"),
          "goal_summary" => plan_view.fetch("goal_summary"),
          "current_item_key" => plan_view.fetch("current_item_key"),
          "current_item_title" => plan_view.dig("current_item", "title"),
          "current_item_status" => plan_view.dig("current_item", "status"),
          "active_item_count" => %w[pending in_progress blocked failed].sum { |status| counts.fetch(status, 0).to_i },
          "completed_item_count" => counts.fetch("completed", 0).to_i,
          "total_item_count" => counts.values.sum(&:to_i),
        }.compact
      end
    end

    def synthetic_turn_feed
      @synthetic_turn_feed ||= plan_items.filter_map do |item|
        event_kind = FEED_EVENT_KIND_BY_STATUS[item.fetch("status")]
        next if event_kind.blank?

        {
          "conversation_id" => @conversation.public_id,
          "turn_id" => feed_turn.public_id,
          "conversation_supervision_feed_entry_id" => stable_public_id("workflow-turn-feed-entry", workflow_plan_view.fetch("turn_todo_plan_id"), item.fetch("item_key"), event_kind),
          "event_kind" => event_kind,
          "summary" => feed_summary_for(event_kind:, title: item.fetch("title")),
          "details_payload" => {
            "item_key" => item.fetch("item_key"),
            "title" => item.fetch("title"),
            "current_status" => item.fetch("status"),
            "current_item_key" => current_item_key,
            "turn_todo_plan_id" => workflow_plan_view.fetch("turn_todo_plan_id"),
          },
          "occurred_at" => item.fetch("occurred_at"),
        }
      end
    end

    def plan_items
      @plan_items ||= visible_nodes.each_with_index.map do |node, position|
        {
          "turn_todo_plan_item_id" => stable_public_id("workflow-turn-todo-plan-item", workflow_plan_view_identity, workflow_item_key(node)),
          "item_key" => workflow_item_key(node),
          "title" => workflow_item_title(node),
          "status" => workflow_item_status(node),
          "position" => position,
          "kind" => workflow_item_kind(node),
          "details_payload" => workflow_item_details(node),
          "depends_on_item_keys" => [],
          "occurred_at" => workflow_item_occurred_at(node).iso8601(6),
        }
      end
    end

    def active_agent_task_run
      return @active_agent_task_run if instance_variable_defined?(:@active_agent_task_run)

      @active_agent_task_run = AgentTaskRun
        .where(conversation: @conversation, lifecycle_state: ACTIVE_TASK_LIFECYCLE_STATES)
        .includes(turn_todo_plan: :turn_todo_plan_items)
        .order(created_at: :desc)
        .first
    end

    def workflow_run
      return @workflow_run if instance_variable_defined?(:@workflow_run)

      @workflow_run = @conversation.workflow_runs.order(created_at: :desc).first
    end

    def feed_turn
      @feed_turn ||= @conversation.turns.where(lifecycle_state: "active").order(sequence: :desc).first ||
        @conversation.turns.order(sequence: :desc).first
    end

    def relevant_nodes
      @relevant_nodes ||= begin
        run = workflow_run
        if run.blank?
          []
        else
          run.workflow_nodes
            .where.not(lifecycle_state: %w[pending queued])
            .order(:ordinal)
            .to_a
            .select { |node| relevant_node?(node) }
        end
      end
    end

    def visible_nodes
      @visible_nodes ||= relevant_nodes.last(3)
    end

    def relevant_node?(node)
      return false if node.node_type == "turn_root"
      return true if node.tool_call_payload.present?
      return true if node.provider_round_index.present?

      node.presentation_policy != "internal_only"
    end

    def current_node
      @current_node ||= relevant_nodes.reverse.find { |node| ACTIVE_WORKFLOW_NODE_STATES.include?(node.lifecycle_state) } ||
        relevant_nodes.last
    end

    def workflow_plan_status
      case workflow_item_status(current_node)
      when "blocked" then "blocked"
      when "completed" then "completed"
      when "failed" then "failed"
      when "canceled" then "canceled"
      else "active"
      end
    end

    def current_item_key
      workflow_item_key(current_node)
    end

    def workflow_item_key(node)
      return "current-turn" if node.blank?

      parts = [node.node_type]
      parts << node.provider_round_index if node.provider_round_index.present?
      parts << node.tool_call_payload&.fetch("tool_name", nil)
      parts << node.node_key
      parts.compact.join("-").parameterize
    end

    def workflow_item_title(node)
      return "Continue current work" if node.blank?

      tool_name = node.tool_call_payload&.fetch("tool_name", nil).presence
      return "Run #{tool_name}" if tool_name.present?
      return "Advance provider round #{node.provider_round_index}" if node.provider_round_index.present?

      node.node_key.to_s.tr("_", " ").strip.presence&.humanize || node.node_type.to_s.humanize
    end

    def workflow_item_status(node)
      return "pending" if node.blank?

      case node.lifecycle_state
      when "completed" then "completed"
      when "failed" then "failed"
      when "canceled" then "canceled"
      when "waiting" then "blocked"
      else "in_progress"
      end
    end

    def workflow_item_kind(node)
      return "implementation" if node.blank?
      return "tool_call" if node.tool_call_payload.present?

      "implementation"
    end

    def workflow_item_details(node)
      return {} if node.blank?

      {
        "workflow_node_id" => node.public_id,
        "workflow_node_key" => node.node_key,
        "workflow_node_type" => node.node_type,
        "provider_round_index" => node.provider_round_index,
        "tool_name" => node.tool_call_payload&.fetch("tool_name", nil),
      }.compact
    end

    def workflow_item_occurred_at(node)
      node&.finished_at || node&.started_at || node&.updated_at || workflow_run&.updated_at || Time.current
    end

    def goal_summary
      @goal_summary ||= begin
        content = feed_turn&.selected_input_message&.content.to_s.squish
        content = workflow_run&.turn&.selected_input_message&.content.to_s.squish if content.blank?
        content.presence&.truncate(160)
      end
    end

    def workflow_plan_view_identity
      @workflow_plan_view_identity ||= stable_public_id("workflow-turn-todo-plan", @conversation.public_id, feed_turn.public_id)
    end

    def stable_public_id(*parts)
      hex = Digest::MD5.hexdigest(parts.join(":"))
      "#{hex[0, 8]}-#{hex[8, 4]}-#{hex[12, 4]}-#{hex[16, 4]}-#{hex[20, 12]}"
    end

    def feed_summary_for(event_kind:, title:)
      case event_kind
      when "turn_todo_item_completed"
        "#{title} completed."
      when "turn_todo_item_blocked"
        "#{title} blocked."
      when "turn_todo_item_canceled"
        "#{title} canceled."
      when "turn_todo_item_failed"
        "#{title} failed."
      else
        "Started #{title.downcase}."
      end
    end
  end
end
