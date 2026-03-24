module ExecutionProfiling
  class SummaryQuery
    Entry = Struct.new(
      :fact_kind,
      :fact_key,
      :event_count,
      :total_count_value,
      :total_duration_ms,
      :success_count,
      :failure_count,
      :last_occurred_at,
      keyword_init: true
    )

    def self.call(...)
      new(...).call
    end

    def initialize(installation:, started_at: nil, ended_at: nil, user: nil, workspace: nil)
      @installation = installation
      @started_at = started_at
      @ended_at = ended_at
      @user = user
      @workspace = workspace
    end

    def call
      scoped_relation
        .group(:fact_kind, :fact_key)
        .order(:fact_kind, :fact_key)
        .pluck(
          :fact_kind,
          :fact_key,
          Arel.sql("COUNT(*)"),
          Arel.sql("COALESCE(SUM(count_value), 0)"),
          Arel.sql("COALESCE(SUM(duration_ms), 0)"),
          Arel.sql("SUM(CASE WHEN success IS TRUE THEN 1 ELSE 0 END)"),
          Arel.sql("SUM(CASE WHEN success IS FALSE THEN 1 ELSE 0 END)"),
          Arel.sql("MAX(occurred_at)")
        )
        .map do |fact_kind, fact_key, event_count, total_count_value, total_duration_ms, success_count, failure_count, last_occurred_at|
          Entry.new(
            fact_kind: fact_kind,
            fact_key: fact_key,
            event_count: event_count,
            total_count_value: total_count_value,
            total_duration_ms: total_duration_ms,
            success_count: success_count,
            failure_count: failure_count,
            last_occurred_at: last_occurred_at
          )
        end
    end

    private

    def scoped_relation
      relation = ExecutionProfileFact.where(installation: @installation)
      relation = relation.where("occurred_at >= ?", @started_at) if @started_at.present?
      relation = relation.where("occurred_at <= ?", @ended_at) if @ended_at.present?
      relation = relation.where(user: @user) if @user.present?
      relation = relation.where(workspace: @workspace) if @workspace.present?
      relation
    end
  end
end
