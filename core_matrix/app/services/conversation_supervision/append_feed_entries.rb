module ConversationSupervision
  class AppendFeedEntries
    def self.call(...)
      new(...).call
    end

    def initialize(conversation:, changeset:, occurred_at: Time.current)
      @conversation = conversation
      @changeset = Array(changeset)
      @occurred_at = occurred_at
    end

    def call
      return [] if normalized_changeset.empty?
      target_turn = self.target_turn
      return [] if target_turn.blank?

      installation = @conversation.installation
      user = @conversation.user
      workspace = @conversation.workspace
      agent = @conversation.agent

      entries = @conversation.with_lock do
        next_sequence = next_sequence_start

        normalized_changeset.map do |change|
          entry = ConversationSupervisionFeedEntry.create!(
            installation: installation,
            user: user,
            workspace: workspace,
            agent: agent,
            target_conversation: @conversation,
            target_turn: target_turn,
            sequence: next_sequence,
            event_kind: change.fetch("event_kind"),
            summary: normalize_summary(change.fetch("summary")),
            details_payload: change.fetch("details_payload"),
            occurred_at: change.fetch("occurred_at")
          )
          next_sequence += 1
          entry
        end
      end

      ConversationSupervision::PruneFeedWindow.call(conversation: @conversation)
      entries
    end

    private

    def normalized_changeset
      @normalized_changeset ||= @changeset.filter_map do |change|
        normalized = change.to_h.deep_stringify_keys
        summary = normalized["summary"].to_s.strip
        next if normalized["event_kind"].blank? || summary.blank?

        {
          "event_kind" => normalized.fetch("event_kind"),
          "summary" => summary,
          "details_payload" => normalized.fetch("details_payload", {}),
          "occurred_at" => normalized["occurred_at"] || @occurred_at,
        }
      end
    end

    def target_turn
      @target_turn ||= @conversation.feed_anchor_turn ||
        @conversation.turns.where(lifecycle_state: "active").order(sequence: :desc).first ||
        @conversation.turns.order(sequence: :desc).first
    end

    def next_sequence_start
      ConversationSupervisionFeedEntry.where(target_conversation: @conversation)
        .maximum(:sequence).to_i + 1
    end

    def normalize_summary(summary)
      sanitized = summary.to_s.gsub(AgentTaskProgressEntry::INTERNAL_RUNTIME_TOKEN_PATTERN, " ").squish
      sanitized.truncate(SupervisionStateFields::HUMAN_SUMMARY_MAX_LENGTH)
    end
  end
end
