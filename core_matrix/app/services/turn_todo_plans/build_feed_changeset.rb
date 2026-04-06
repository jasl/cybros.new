module TurnTodoPlans
  class BuildFeedChangeset
    STATUS_EVENT_KIND = {
      "completed" => "turn_todo_item_completed",
      "blocked" => "turn_todo_item_blocked",
      "canceled" => "turn_todo_item_canceled",
      "failed" => "turn_todo_item_failed",
      "in_progress" => "turn_todo_item_started",
    }.freeze

    def self.call(...)
      new(...).call
    end

    def initialize(previous_plan:, current_plan:, occurred_at: Time.current)
      @previous_plan = normalize_plan(previous_plan)
      @current_plan = normalize_plan(current_plan)
      @occurred_at = occurred_at
    end

    def call
      current_items.each_with_object([]) do |item, changeset|
        previous_item = previous_items_by_key[item.fetch("item_key")]
        previous_status = previous_item&.fetch("status", nil)
        current_status = item.fetch("status")

        if previous_status != current_status
          event_kind = STATUS_EVENT_KIND[current_status]
          if event_kind.present?
            changeset << build_change(
              event_kind: event_kind,
              item: item,
              previous_status: previous_status,
              current_status: current_status
            )
          end
        end

        next unless started_current_item?(item)
        next if changeset.any? { |entry| entry.fetch("event_kind") == "turn_todo_item_started" && entry.dig("details_payload", "item_key") == item.fetch("item_key") }

        changeset << build_change(
          event_kind: "turn_todo_item_started",
          item: item,
          previous_status: previous_status,
          current_status: current_status
        )
      end
    end

    private

    def normalize_plan(plan)
      return {} if plan.blank?

      plan.to_h.deep_stringify_keys
    end

    def current_items
      @current_items ||= Array(@current_plan["items"]).map { |item| item.to_h.deep_stringify_keys }
    end

    def previous_items_by_key
      @previous_items_by_key ||= Array(@previous_plan["items"]).each_with_object({}) do |item, items|
        normalized = item.to_h.deep_stringify_keys
        items[normalized.fetch("item_key")] = normalized
      end
    end

    def started_current_item?(item)
      current_item_key = @current_plan["current_item_key"]
      return false if current_item_key.blank?
      return false unless item.fetch("item_key") == current_item_key
      return false if @previous_plan["current_item_key"] == current_item_key

      true
    end

    def build_change(event_kind:, item:, previous_status:, current_status:)
      {
        "event_kind" => event_kind,
        "summary" => summary_for(event_kind:, title: item.fetch("title")),
        "details_payload" => {
          "item_key" => item.fetch("item_key"),
          "title" => item.fetch("title"),
          "previous_status" => previous_status,
          "current_status" => current_status,
          "current_item_key" => @current_plan["current_item_key"],
          "turn_todo_plan_id" => @current_plan["turn_todo_plan_id"],
        }.compact,
        "occurred_at" => @occurred_at,
      }
    end

    def summary_for(event_kind:, title:)
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
