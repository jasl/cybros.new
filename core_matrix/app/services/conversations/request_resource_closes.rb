module Conversations
  class RequestResourceCloses
    def self.call(...)
      new(...).call
    end

    def initialize(relations:, request_kind:, reason_kind:, occurred_at: Time.current, strictness: "graceful")
      @relations = relations.is_a?(Array) ? relations : [relations]
      @request_kind = request_kind
      @reason_kind = reason_kind
      @occurred_at = occurred_at
      @strictness = strictness
    end

    def call
      each_resource do |resource|
        next unless resource.close_open?

        AgentControl::CreateResourceCloseRequest.call(
          resource: resource,
          request_kind: @request_kind,
          reason_kind: @reason_kind,
          strictness: @strictness,
          **close_request_deadlines
        )
      end
    end

    private

    def each_resource
      @relations.each do |relation|
        relation.find_each do |resource|
          yield resource
        end
      end
    end

    def close_request_deadlines
      @close_request_deadlines ||= CloseRequestSchedule.deadlines_for(occurred_at: @occurred_at)
    end
  end
end
