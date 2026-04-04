class AddBundleSnapshotToConversationObservationFrames < ActiveRecord::Migration[8.0]
  def change
    add_column :conversation_observation_frames, :bundle_snapshot, :jsonb, default: {}, null: false
  end
end
