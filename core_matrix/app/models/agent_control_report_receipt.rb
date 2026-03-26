class AgentControlReportReceipt < ApplicationRecord
  belongs_to :installation
  belongs_to :agent_deployment
  belongs_to :agent_task_run, optional: true
  belongs_to :mailbox_item, class_name: "AgentControlMailboxItem", optional: true

  validates :message_id, presence: true, uniqueness: { scope: :installation_id }
  validates :method_id, presence: true
  validates :result_code, presence: true
  validate :payload_must_be_hash

  private

  def payload_must_be_hash
    errors.add(:payload, "must be a hash") unless payload.is_a?(Hash)
  end
end
