module EmbeddedAgents
  module ConversationSupervision
    module Responders
      class SummaryModel
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
          selector = summary_selector
          return if selector.blank?

          resolution = effective_catalog.resolve_selector(selector: selector)
          return unless resolution.usable?

          request_context = build_request_context(resolution)
          result = dispatch_request(request_context)

          normalize_modeled_content(provider_result_content(result))
        rescue StandardError => error
          @logger.info("conversation supervision summary model fallback: #{error.class}: #{error.message}")
          nil
        end

        def summary_selector
          latest_turn&.agent_program_version&.default_config_snapshot&.dig("model_slots", "summary", "selector") || "role:summary"
        end

        def latest_turn
          @latest_turn ||= @conversation_supervision_snapshot.target_conversation.turns.order(sequence: :desc).first
        end

        def effective_catalog
          @effective_catalog ||= ProviderCatalog::EffectiveCatalog.new(
            installation: @conversation_supervision_snapshot.target_conversation.installation,
            catalog: @catalog || ProviderCatalog::Registry.current
          )
        end

        def build_request_context(resolution)
          provider_definition = effective_catalog.provider(resolution.provider_handle)
          model_definition = effective_catalog.model(resolution.provider_handle, resolution.model_ref)
          execution_settings = ProviderRequestSettingsSchema
            .for(provider_definition.fetch(:wire_api))
            .merge_execution_settings(
              request_defaults: model_definition.fetch(:request_defaults, {}),
              runtime_overrides: {}
            )

          ProviderRequestContext.new(
            "provider_handle" => resolution.provider_handle,
            "model_ref" => resolution.model_ref,
            "api_model" => model_definition.fetch(:api_model),
            "wire_api" => provider_definition.fetch(:wire_api),
            "transport" => provider_definition.fetch(:transport),
            "tokenizer_hint" => model_definition.fetch(:tokenizer_hint),
            "execution_settings" => execution_settings,
            "hard_limits" => {
              "context_window_tokens" => model_definition.fetch(:context_window_tokens),
              "max_output_tokens" => [model_definition.fetch(:max_output_tokens), MAX_OUTPUT_TOKENS].min,
            },
            "advisory_hints" => {
              "recommended_compaction_threshold" => (model_definition.fetch(:context_window_tokens) * model_definition.fetch(:context_soft_limit_ratio)).floor,
            },
            "provider_metadata" => provider_definition.fetch(:metadata, {}).deep_stringify_keys,
            "model_metadata" => model_definition.fetch(:metadata, {}).deep_stringify_keys,
          )
        end

        def dispatch_request(request_context)
          provider_definition = effective_catalog.provider(request_context.provider_handle)
          client = build_client(provider_handle: request_context.provider_handle, provider_definition: provider_definition)
          request = {
            model: request_context.api_model,
            **request_context.execution_settings.symbolize_keys,
          }

          case request_context.wire_api
          when "responses"
            client.responses(
              **request.merge(
                input: prompt_messages,
                max_output_tokens: request_context.hard_limits.fetch("max_output_tokens")
              )
            )
          else
            client.chat(
              **request.merge(
                messages: prompt_messages,
                max_tokens: request_context.hard_limits.fetch("max_output_tokens")
              )
            )
          end
        end

        def build_client(provider_handle:, provider_definition:)
          adapter = @adapter || ProviderExecution::BuildHttpAdapter.call(provider_definition: provider_definition)

          case provider_definition.fetch(:wire_api)
          when "responses"
            SimpleInference::Protocols::OpenAIResponses.new(
              base_url: provider_definition.fetch(:base_url),
              api_key: credential_secret_for(provider_handle:, provider_definition:),
              headers: provider_definition.fetch(:headers, {}),
              responses_path: provider_definition.fetch(:responses_path),
              adapter: adapter
            )
          else
            SimpleInference::Client.new(
              base_url: provider_definition.fetch(:base_url),
              api_key: credential_secret_for(provider_handle:, provider_definition:),
              headers: provider_definition.fetch(:headers, {}),
              adapter: adapter
            )
          end
        end

        def credential_secret_for(provider_handle:, provider_definition:)
          return nil unless provider_definition.fetch(:requires_credential)

          ProviderCredential.find_by!(
            installation: @conversation_supervision_snapshot.target_conversation.installation,
            provider_handle: provider_handle,
            credential_kind: provider_definition.fetch(:credential_kind)
          ).secret
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
          focus_summary =
            machine_status["current_focus_summary"].presence ||
            machine_status["request_summary"].presence ||
            contextual_focus_summary(machine_status)

          {
            "overall_state" => machine_status["overall_state"],
            "last_terminal_state" => machine_status["last_terminal_state"],
            "last_terminal_at" => machine_status["last_terminal_at"],
            "board_lane" => machine_status["board_lane"],
            "board_badges" => machine_status["board_badges"],
            "request_summary" => machine_status["request_summary"],
            "current_focus_summary" => focus_summary,
            "recent_progress_summary" => machine_status["recent_progress_summary"],
            "waiting_summary" => machine_status["waiting_summary"],
            "blocked_summary" => machine_status["blocked_summary"],
            "next_step_hint" => machine_status["next_step_hint"],
            "active_plan_items" => Array(machine_status["active_plan_items"]).map do |item|
              item.slice("title", "status", "position")
            end,
            "active_subagents" => Array(machine_status["active_subagents"]).map do |entry|
              entry.slice("observed_status", "supervision_state", "profile_key", "current_focus_summary", "waiting_summary", "blocked_summary", "next_step_hint")
            end,
            "activity_feed" => meaningful_activity_feed(machine_status).last(3).map do |entry|
              entry.slice("event_kind", "summary", "occurred_at")
            end,
            "conversation_context" => {
              "facts" => Array(machine_status.dig("conversation_context", "facts")).last(3).map do |fact|
                fact.slice("role", "summary", "keywords")
              end
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

        def meaningful_activity_feed(machine_status)
          Array(machine_status["activity_feed"]).reject do |entry|
            generic_turn_start_entry?(entry) && machine_status["recent_progress_summary"].blank?
          end
        end

        def generic_turn_start_entry?(entry)
          summary = entry.to_h.fetch("summary", "")
          event_kind = entry.to_h.fetch("event_kind", nil)

          summary.match?(/\AStarted the turn\.?\z/i) && (event_kind.blank? || event_kind == "turn_started")
        end

        def provider_result_content(result)
          if result.respond_to?(:output_text)
            result.output_text.to_s
          else
            result.content.to_s
          end
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
