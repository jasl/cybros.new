require "json"
require "pathname"
require "securerandom"

module Acceptance
  module SupervisionEvalReplay
    module_function

    DEFAULT_PROMPT = "Please tell me what you are doing right now and what changed most recently.".freeze

    SyntheticConversation = Struct.new(:public_id, :installation, keyword_init: true)
    SyntheticSnapshot = Struct.new(:public_id, :target_conversation, :machine_status_payload, keyword_init: true)
    SyntheticSession = Struct.new(:public_id, keyword_init: true)

    def run!(bundle_path:)
      bundle_file = Pathname(bundle_path).expand_path
      bundle = JSON.parse(bundle_file.read)
      prompt = bundle["prompt"].presence || DEFAULT_PROMPT
      questions = Array(bundle["questions"]).presence || [prompt]
      machine_status = bundle.fetch("machine_status").to_h

      session = SyntheticSession.new(public_id: machine_status["supervision_session_id"].presence || SecureRandom.uuid)
      conversation = SyntheticConversation.new(
        public_id: machine_status["conversation_id"].presence || SecureRandom.uuid,
        installation: nil
      )
      snapshot = SyntheticSnapshot.new(
        public_id: machine_status["supervision_snapshot_id"].presence || SecureRandom.uuid,
        target_conversation: conversation,
        machine_status_payload: machine_status
      )

      polls = questions.map do |question|
        response = EmbeddedAgents::ConversationSupervision::Responders::Builtin.call(
          conversation_supervision_session: session,
          conversation_supervision_snapshot: snapshot,
          question: question
        )

        {
          "machine_status" => machine_status,
          "human_sidechat" => response.fetch("human_sidechat"),
          "user_message" => { "content" => question },
        }
      end

      final_response = EmbeddedAgents::ConversationSupervision::Responders::Builtin.call(
        conversation_supervision_session: session,
        conversation_supervision_snapshot: snapshot,
        question: questions.last
      )

      supervision_trace = {
        "session" => {
          "conversation_supervision_session" => {
            "supervision_session_id" => session.public_id,
          },
        },
        "polls" => polls,
        "final_response" => final_response,
      }

      review_dir = bundle_file.dirname
      write_text(
        review_dir.join("supervision-sidechat.md"),
        Acceptance::ConversationArtifacts.supervision_sidechat_markdown(
          supervision_trace: supervision_trace,
          prompt: prompt
        )
      )
      write_text(
        review_dir.join("supervision-status.md"),
        Acceptance::ConversationArtifacts.supervision_status_markdown(
          supervision_trace: supervision_trace
        )
      )
      write_text(
        review_dir.join("supervision-feed.md"),
        Acceptance::ConversationArtifacts.supervision_feed_markdown(
          supervision_trace: supervision_trace
        )
      )

      replay_result = {
        "bundle_path" => bundle_file.to_s,
        "review_dir" => review_dir.to_s,
        "prompt" => prompt,
        "questions" => questions,
        "responder_kind" => "builtin",
      }
      write_json(review_dir.join("supervision-replay.json"), replay_result.merge(
        "final_response" => final_response,
        "poll_count" => polls.length
      ))

      replay_result
    end

    def write_text(path, contents)
      path.dirname.mkpath
      path.binwrite(contents)
    end
    private_class_method :write_text

    def write_json(path, payload)
      path.dirname.mkpath
      path.write(JSON.pretty_generate(payload) + "\n")
    end
    private_class_method :write_json
  end
end
