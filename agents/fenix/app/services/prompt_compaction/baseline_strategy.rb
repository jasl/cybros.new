module PromptCompaction
  class BaselineStrategy
    PRESERVATION_INVARIANTS = [
      "newest_selected_input_verbatim",
      "explicit_user_constraints_preserved",
      "active_paths_and_identifiers_preserved",
      "unresolved_errors_preserved",
    ].freeze
    PATH_PATTERN = %r{(?:/[A-Za-z0-9._/\-]+|[A-Za-z0-9_\-./]+\.[A-Za-z0-9]+)}.freeze
    IMPORTANT_TOKEN_PATTERN = /\b(?:[A-Z][A-Z0-9_-]{2,}|[A-Za-z]+Error)\b/.freeze
    CHARS_PER_TOKEN = 4.0
    MAX_CAPTURED_VALUES = 8

    def self.call(...)
      new(...).call
    end

    def initialize(messages:, hard_input_token_limit:, recommended_compaction_threshold:, selected_input_message_id:)
      @messages = Array(messages).map { |entry| entry.deep_stringify_keys }
      @hard_input_token_limit = hard_input_token_limit.to_i
      @recommended_compaction_threshold = recommended_compaction_threshold.to_i
      @selected_input_message_id = selected_input_message_id
    end

    def call
      before_estimate = estimate(@messages)
      return selected_input_too_large(before_estimate) if latest_input_too_large?
      return unchanged_result(before_estimate, "within_budget") if within_budget?(before_estimate)

      compacted_messages = compacted_message_sequence
      after_estimate = estimate(compacted_messages)

      if after_estimate.fetch("estimated_tokens") > @hard_input_token_limit
        compacted_messages = minimal_message_sequence
        after_estimate = estimate(compacted_messages)
      end

      if after_estimate.fetch("estimated_tokens") > @hard_input_token_limit
        return unchanged_result(before_estimate, "hard_limit_after_compaction", failure_scope: "full_context")
      end

      {
        "compacted" => compacted_messages != @messages,
        "messages" => compacted_messages,
        "selected_input_message_id" => @selected_input_message_id,
        "before_estimate" => before_estimate,
        "after_estimate" => after_estimate,
        "stop_reason" => compacted_messages == @messages ? "no_reduction_needed" : "compacted",
        "failure_scope" => nil,
        "preservation_invariants" => PRESERVATION_INVARIANTS,
        "diagnostics" => diagnostics.merge(
          "summarized_message_count" => middle_messages.length
        ),
      }
    end

    private

    def latest_input_too_large?
      estimate([latest_message]).fetch("estimated_tokens") > @hard_input_token_limit
    end

    def within_budget?(estimate_result)
      estimated_tokens = estimate_result.fetch("estimated_tokens")
      estimated_tokens <= @hard_input_token_limit &&
        estimated_tokens <= @recommended_compaction_threshold
    end

    def selected_input_too_large(before_estimate)
      unchanged_result(
        before_estimate,
        "selected_input_exceeds_hard_limit",
        failure_scope: "current_input"
      )
    end

    def unchanged_result(before_estimate, stop_reason, failure_scope: nil)
      {
        "compacted" => false,
        "messages" => @messages.deep_dup,
        "selected_input_message_id" => @selected_input_message_id,
        "before_estimate" => before_estimate,
        "after_estimate" => before_estimate,
        "stop_reason" => stop_reason,
        "failure_scope" => failure_scope,
        "preservation_invariants" => PRESERVATION_INVARIANTS,
        "diagnostics" => diagnostics.merge(
          "summarized_message_count" => middle_messages.length
        ),
      }
    end

    def compacted_message_sequence
      messages = leading_system_messages.map(&:deep_dup)
      summary = summary_message
      messages << summary if summary.present?
      messages << latest_message.deep_dup
      deduplicate_consecutive_messages(messages)
    end

    def minimal_message_sequence
      deduplicate_consecutive_messages(
        leading_system_messages.map(&:deep_dup) + [latest_message.deep_dup]
      )
    end

    def deduplicate_consecutive_messages(messages)
      messages.each_with_object([]) do |message, memo|
        memo << message unless memo.last == message
      end
    end

    def summary_message
      return if middle_messages.empty?

      lines = ["Compacted earlier context:"]
      lines << "- Prior user goals: #{prior_user_goals.join(' | ')}" if prior_user_goals.present?
      lines << "- Important paths: #{important_paths.join(', ')}" if important_paths.present?
      lines << "- Important tokens: #{important_tokens.join(', ')}" if important_tokens.present?
      lines << "- Recent context: #{recent_context_excerpt}" if recent_context_excerpt.present?

      {
        "role" => "system",
        "content" => lines.join("\n"),
      }
    end

    def leading_system_messages
      @leading_system_messages ||= begin
        collected = []
        @messages.each do |message|
          break unless message["role"] == "system"

          collected << message
        end
        collected
      end
    end

    def latest_message
      @latest_message ||= @messages.last || { "role" => "user", "content" => "" }
    end

    def middle_messages
      @middle_messages ||= begin
        start_index = leading_system_messages.length
        end_index = @messages.length - 2
        return [] if end_index < start_index

        @messages[start_index..end_index] || []
      end
    end

    def prior_user_goals
      @prior_user_goals ||= middle_messages
        .select { |message| message["role"] == "user" }
        .map { |message| truncate_text(message["content"], 180) }
        .reject(&:blank?)
        .first(2)
    end

    def important_paths
      @important_paths ||= scan_values(PATH_PATTERN)
    end

    def important_tokens
      @important_tokens ||= scan_values(IMPORTANT_TOKEN_PATTERN)
    end

    def recent_context_excerpt
      source = middle_messages.reverse.find { |message| message["content"].present? }
      truncate_text(source&.fetch("content", nil), 220)
    end

    def scan_values(pattern)
      middle_messages
        .flat_map { |message| message.fetch("content", "").to_s.scan(pattern) }
        .map(&:to_s)
        .uniq
        .first(MAX_CAPTURED_VALUES)
    end

    def diagnostics
      {
        "important_paths" => important_paths,
        "important_tokens" => important_tokens,
      }
    end

    def estimate(messages)
      estimated_tokens = Array(messages).sum do |message|
        [(message.fetch("content", "").to_s.length / CHARS_PER_TOKEN).ceil, 1].max
      end

      {
        "estimated_tokens" => estimated_tokens,
        "strategy" => "heuristic",
      }
    end

    def truncate_text(value, max_length)
      candidate = value.to_s.squish
      return if candidate.blank?
      return candidate if candidate.length <= max_length

      "#{candidate[0, max_length - 3]}..."
    end
  end
end
