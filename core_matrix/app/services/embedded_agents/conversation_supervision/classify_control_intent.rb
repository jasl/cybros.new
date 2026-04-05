module EmbeddedAgents
  module ConversationSupervision
    class ClassifyControlIntent
      Result = Struct.new(
        :matched,
        :request_kind,
        :request_payload,
        keyword_init: true
      ) do
        def matched?
          matched == true
        end
      end

      def self.call(...)
        new(...).call
      end

      def initialize(question:)
        @question = question.to_s
      end

      def call
        return matched_result("request_subagent_close") if subagent_close_phrase?
        return matched_result("request_conversation_close", "intent_kind" => "archive") if conversation_close_phrase?
        return matched_result("resume_waiting_workflow") if resume_phrase?
        return matched_result("retry_blocked_step") if retry_phrase?
        return matched_result("request_turn_interrupt") if stop_phrase?

        Result.new(matched: false, request_kind: nil, request_payload: {})
      end

      private

      def matched_result(request_kind, request_payload = {})
        Result.new(
          matched: true,
          request_kind: request_kind,
          request_payload: request_payload.deep_stringify_keys
        )
      end

      def normalized_question
        @normalized_question ||= @question.downcase.gsub(/[[:punct:]]+/, " ").squish
      end

      def stop_phrase?
        exact_match?(%w[stop pause abort interrupt]) ||
          chinese_exact_match?(%w[快住手 别继续了 停下 先停一下])
      end

      def conversation_close_phrase?
        chinese_exact_match?(["关闭这个任务"]) ||
          normalized_question.match?(/\A(?:close|archive)\b.*\b(?:task|conversation|this)\b/)
      end

      def subagent_close_phrase?
        chinese_exact_match?(["让子任务停下"]) ||
          normalized_question.match?(/\A(?:stop|close)\b.*\b(?:subagent|child|worker)\b/)
      end

      def resume_phrase?
        chinese_exact_match?(["继续执行"]) ||
          normalized_question.match?(/\A(?:resume|continue)\b.*\b(?:workflow|task|work)\b/)
      end

      def retry_phrase?
        chinese_exact_match?(["重试这一步"]) ||
          normalized_question.match?(/\A(?:retry|try again)\b.*\b(?:step|blocked)\b/)
      end

      def exact_match?(terms)
        terms.include?(normalized_question)
      end

      def chinese_exact_match?(phrases)
        phrases.include?(normalized_chinese_question)
      end

      def normalized_chinese_question
        @normalized_chinese_question ||= @question.gsub(/[[:space:][:punct:]“”‘’！？。、「」『』（）【】]/, "")
      end
    end
  end
end
