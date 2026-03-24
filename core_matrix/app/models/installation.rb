class Installation < ApplicationRecord
  BOOTSTRAP_STATES = %w[pending bootstrapped].freeze

  has_many :users, dependent: :destroy
  has_many :invitations, dependent: :destroy
  has_many :audit_logs, dependent: :destroy
  has_many :agent_installations, dependent: :destroy
  has_many :execution_environments, dependent: :destroy
  has_many :agent_enrollments, dependent: :destroy
  has_many :agent_deployments, dependent: :destroy

  validates :name, presence: true
  validates :bootstrap_state, presence: true, inclusion: { in: BOOTSTRAP_STATES }
  validate :single_row_installation, on: :create
  validate :global_settings_must_be_hash

  def pending? = bootstrap_state == "pending"

  def bootstrapped? = bootstrap_state == "bootstrapped"

  private

  def single_row_installation
    errors.add(:base, "installation already exists") if self.class.where.not(id: id).exists?
  end

  def global_settings_must_be_hash
    errors.add(:global_settings, "must be a Hash") unless global_settings.is_a?(Hash)
  end
end
