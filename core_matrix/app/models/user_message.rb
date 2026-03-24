class UserMessage < Message
  validate :user_role_and_slot

  private

  def user_role_and_slot
    errors.add(:role, "must be user") unless user?
    errors.add(:slot, "must be input") unless input?
  end
end
