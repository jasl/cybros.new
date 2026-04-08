class AddGuidanceProjectionIndexesToConversationControlRequests < ActiveRecord::Migration[8.2]
  def change
    add_index :conversation_control_requests,
      [:installation_id, :request_kind, :lifecycle_state, :target_conversation_id, :completed_at],
      name: "idx_ccr_guidance_projection_conversation"

    add_index :conversation_control_requests,
      [:installation_id, :request_kind, :lifecycle_state, :target_public_id, :completed_at],
      name: "idx_ccr_guidance_projection_subagent"
  end
end
