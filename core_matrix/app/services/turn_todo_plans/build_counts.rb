module TurnTodoPlans
  class BuildCounts
    def self.call(...)
      new(...).call
    end

    def initialize(items:)
      @items = Array(items)
    end

    def call
      TurnTodoPlanItem::STATUSES.index_with(0).tap do |counts|
        @items.each do |item|
          status = status_for(item)
          next if status.blank?

          counts[status] = counts.fetch(status, 0) + 1
        end
      end
    end

    private

    def status_for(item)
      return item.status if item.respond_to?(:status)

      item.to_h.fetch("status")
    end
  end
end
