class CreateConversationCapabilityPolicies < ActiveRecord::Migration[8.2]
  def change
    # Removed before launch. Capability authority is projected directly onto
    # conversations instead of being stored in a separate policy table.
  end
end
