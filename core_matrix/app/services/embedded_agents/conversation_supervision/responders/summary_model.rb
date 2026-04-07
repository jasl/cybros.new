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
          If supervision.overall_state is idle, the first sentence must explicitly say the conversation is idle.
          Do not paraphrase idle as merely "not doing anything" or describe active work for an idle state.
          Prefer the active plan item and recent plan transitions over runtime details.
          If current_focus_summary is generic or missing and runtime_facts.active_focus_summary is present, use that runtime fact as the current-status sentence instead of restating request_summary or context snippets.
          If recent plan progress is unavailable and runtime_facts.recent_progress_summary is present, use it for the recent-change sentence.
          Use runtime evidence only to justify waiting, blocking, or coarse fallback status.
          Mention a next step only when the user asks and the payload includes a justified next_step_hint.
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

          modeled_content = render_modeled_content(machine_status: machine_status)
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

        def render_modeled_content(machine_status:)
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

          normalized = normalize_modeled_content(result.content)
          return normalized if acceptable_modeled_content?(normalized, machine_status)

          @logger.info("conversation supervision summary model fallback: unacceptable modeled content for #{machine_status.fetch("overall_state")}")
          nil
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
            "supervision" => Responders::BuildPromptPayload.call(
              machine_status: @conversation_supervision_snapshot.machine_status_payload
            ),
          }
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

        def acceptable_modeled_content?(content, machine_status)
          return false if content.blank?
          return true unless machine_status.fetch("overall_state") == "idle"

          content.match?(/\bidle\b/i) && !content.match?(/\bwaiting\b|\bblocked\b|\bworking on\b/i)
        end
      end
    end
  end
end
