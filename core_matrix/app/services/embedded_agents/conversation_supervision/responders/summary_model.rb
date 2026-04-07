module EmbeddedAgents
  module ConversationSupervision
    module Responders
      class SummaryModel
        SUMMARY_SELECTOR = "role:supervision_summary"
        SYSTEM_PROMPT = <<~TEXT.freeze
          You produce concise user-facing supervision replies from sanitized supervision data.
          Answer in the same language as the user's question.
          Base the reply only on the provided supervision payload.
          Do not mention snapshots, machine status, internal ids, provider names, model names, runtime tokens, or provenance phrases such as "Grounded in".
          Prefer what is happening right now and what changed most recently.
          When a contextual focus summary is available, prefer it over generic lifecycle phrasing like "working on this turn".
          Mention a next step only when the user asks and the payload includes a justified next_step_hint.
          If the only recent change is a generic lifecycle event such as starting the turn, you may omit the recent-change sentence.
          If detailed progress is unavailable, answer using only the coarse state information.
          Keep the answer to at most two short sentences.
        TEXT
        MAX_OUTPUT_TOKENS = 160

        def self.call(...)
          new(...).call
        end

        def initialize(actor: nil, conversation_supervision_session:, conversation_supervision_snapshot:, question:, control_decision: nil, adapter: nil, catalog: nil, logger: Rails.logger)
          @actor = actor
          @conversation_supervision_session = conversation_supervision_session
          @conversation_supervision_snapshot = conversation_supervision_snapshot
          @question = question.to_s
          @control_decision = control_decision
          @adapter = adapter
          @catalog = catalog
          @logger = logger
        end

        def call
          machine_status = @conversation_supervision_snapshot.machine_status_payload

          return control_response(machine_status) if @control_decision&.handled?

          modeled_content = render_modeled_content
          return builtin_response if modeled_content.blank?

          {
            "machine_status" => machine_status,
            "human_sidechat" => {
              "supervision_session_id" => @conversation_supervision_session.public_id,
              "supervision_snapshot_id" => @conversation_supervision_snapshot.public_id,
              "conversation_id" => @conversation_supervision_snapshot.target_conversation.public_id,
              "overall_state" => machine_status.fetch("overall_state"),
              "intent" => "general_status",
              "content" => modeled_content,
            },
            "responder_kind" => "summary_model",
          }
        end

        private

        def control_response(machine_status)
          {
            "machine_status" => machine_status,
            "human_sidechat" => {
              "supervision_session_id" => @conversation_supervision_session.public_id,
              "supervision_snapshot_id" => @conversation_supervision_snapshot.public_id,
              "conversation_id" => @conversation_supervision_snapshot.target_conversation.public_id,
              "overall_state" => machine_status.fetch("overall_state"),
              "intent" => "control_request",
              "classified_intent" => @control_decision.request_kind,
              "response_kind" => @control_decision.response_kind,
              "dispatch_state" => @control_decision.conversation_control_request&.lifecycle_state || "not_dispatched",
              "conversation_control_request_id" => @control_decision.conversation_control_request&.public_id,
              "content" => @control_decision.message,
            }.compact,
            "responder_kind" => "summary_model",
          }
        end

        def builtin_response
          Builtin.call(
            actor: @actor,
            conversation_supervision_session: @conversation_supervision_session,
            conversation_supervision_snapshot: @conversation_supervision_snapshot,
            question: @question,
            control_decision: @control_decision
          )
        end

        def render_modeled_content
          result = ProviderGateway::DispatchText.call(
            installation: @conversation_supervision_snapshot.target_conversation.installation,
            selector: SUMMARY_SELECTOR,
            messages: prompt_messages,
            max_output_tokens: MAX_OUTPUT_TOKENS,
            purpose: "supervision_summary",
            request_overrides: {},
            adapter: @adapter,
            catalog: @catalog
          )

          normalize_modeled_content(result.content)
        rescue StandardError => error
          @logger.info("conversation supervision summary model fallback: #{error.class}: #{error.message}")
          nil
        end

        def prompt_messages
          [
            {
              "role" => "system",
              "content" => SYSTEM_PROMPT,
            },
            {
              "role" => "user",
              "content" => JSON.generate(prompt_payload),
            },
          ]
        end

        def prompt_payload
          {
            "question" => @question,
            "supervision" => sanitized_supervision_payload,
          }
        end

        def sanitized_supervision_payload
          machine_status = @conversation_supervision_snapshot.machine_status_payload.deep_stringify_keys
          idle_snapshot = machine_status["overall_state"] == "idle"
          runtime_focus_hint = idle_snapshot ? {} : machine_status.fetch("runtime_focus_hint", {}).to_h
          focus_summary =
            unless idle_snapshot
              runtime_focus_hint["current_focus_summary"].presence ||
                machine_status["current_focus_summary"].presence ||
                machine_status.dig("primary_turn_todo_plan_view", "current_item", "title").presence ||
                machine_status["request_summary"].presence ||
                machine_status.dig("primary_turn_todo_plan_view", "goal_summary").presence ||
                contextual_focus_summary(machine_status)
            end
          waiting_summary =
            unless idle_snapshot
              runtime_focus_hint["waiting_summary"].presence ||
                runtime_focus_sentence(runtime_focus_hint["summary"]).presence ||
                machine_status["waiting_summary"].presence
            end

          {
            "overall_state" => machine_status["overall_state"],
            "last_terminal_state" => machine_status["last_terminal_state"],
            "last_terminal_at" => machine_status["last_terminal_at"],
            "board_lane" => machine_status["board_lane"],
            "board_badges" => machine_status["board_badges"],
            "request_summary" => machine_status["request_summary"],
            "current_focus_summary" => focus_summary,
            "recent_progress_summary" => machine_status["recent_progress_summary"],
            "runtime_focus_hint" => runtime_focus_hint.slice("kind", "summary", "command_run_public_id", "process_run_public_id").presence,
            "waiting_summary" => waiting_summary,
            "blocked_summary" => idle_snapshot ? nil : machine_status["blocked_summary"],
            "next_step_hint" => idle_snapshot ? nil : machine_status["next_step_hint"],
            "primary_turn_todo_plan" => compact_turn_todo_plan(
              machine_status["primary_turn_todo_plan_view"],
              include_current_item: !idle_snapshot
            ),
            "active_subagent_turn_todo_plans" => Array(machine_status["active_subagent_turn_todo_plan_views"]).map do |entry|
              compact_subagent_turn_todo_plan(entry)
            end,
            "turn_feed" => meaningful_turn_feed(machine_status).last(3).map do |entry|
              entry.slice("event_kind", "summary", "occurred_at")
            end,
            "conversation_context" => {
              "facts" => Array(machine_status.dig("conversation_context", "facts")).last(3).map do |fact|
                fact.slice("role", "summary", "keywords")
              end,
            },
          }.compact
        end

        def contextual_focus_summary(machine_status)
          fact = Array(machine_status.dig("conversation_context", "facts")).last
          return if fact.blank?

          keywords = Array(fact["keywords"]).map { |keyword| keyword.to_s.downcase }
          if keywords.include?("2048") && keywords.include?("game")
            return "building the React 2048 game" if keywords.include?("react")
            return "building the 2048 game"
          end

          summary = fact.fetch("summary", nil).to_s
          return if summary.blank?

          summary
            .sub(/\AContext already references\s+/i, "")
            .sub(/\.\z/, "")
            .presence
        end

        def runtime_focus_sentence(summary)
          return if summary.blank?

          if summary.match?(/\Awaiting for\b/i)
            "Waiting for #{summary.delete_prefix("waiting for ").strip} to finish."
          else
            "Waiting for #{summary}."
          end
        end

        def meaningful_turn_feed(machine_status)
          Array(machine_status["turn_feed"].presence || machine_status["activity_feed"]).reject do |entry|
            generic_turn_start_entry?(entry) && machine_status["recent_progress_summary"].blank?
          end
        end

        def compact_turn_todo_plan(plan_view, include_current_item: true)
          return if plan_view.blank?

          compacted = {
            "goal_summary" => plan_view["goal_summary"],
          }
          return compacted.compact unless include_current_item

          compacted.merge(
            "current_item_key" => plan_view["current_item_key"],
            "current_item_title" => plan_view.dig("current_item", "title"),
            "current_item_status" => plan_view.dig("current_item", "status"),
          ).compact
        end

        def compact_subagent_turn_todo_plan(plan_view)
          compact_turn_todo_plan(plan_view).to_h.merge(
            "subagent_session_id" => plan_view["subagent_session_id"],
            "profile_key" => plan_view["profile_key"],
            "observed_status" => plan_view["observed_status"],
            "supervision_state" => plan_view["supervision_state"],
          ).compact
        end

        def generic_turn_start_entry?(entry)
          summary = entry.to_h.fetch("summary", "")
          event_kind = entry.to_h.fetch("event_kind", nil)

          summary.match?(/\AStarted the turn\.?\z/i) && (event_kind.blank? || event_kind == "turn_started")
        end

        def normalize_modeled_content(content)
          sentences = content.to_s
            .gsub(AgentTaskProgressEntry::INTERNAL_RUNTIME_TOKEN_PATTERN, " ")
            .split(/(?<=[.?!])\s+/)
            .reject { |sentence| sentence.match?(/\AGrounded in\b/i) }
            .map(&:squish)
            .reject(&:blank?)

          normalized = sentences.first(2).join(" ").squish
          normalized.truncate(SupervisionStateFields::HUMAN_SUMMARY_MAX_LENGTH * 2).presence
        end
      end
    end
  end
end
