class AgentMessage < Message
  validate :agent_role_and_slot

  private

  def agent_role_and_slot
    errors.add(:role, "must be agent") unless agent?
    errors.add(:slot, "must be output") unless output?
  end
end
