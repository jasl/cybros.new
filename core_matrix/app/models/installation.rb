class Installation < ApplicationRecord
  BOOTSTRAP_STATES = %w[pending bootstrapped].freeze

  has_many :users, dependent: :destroy
  has_many :invitations, dependent: :destroy
  has_many :audit_logs, dependent: :destroy
  has_many :json_documents, dependent: :destroy
  has_many :agents, dependent: :destroy
  has_many :execution_runtimes, dependent: :destroy
  has_many :onboarding_sessions, dependent: :destroy
  has_many :agent_definition_versions, dependent: :destroy
  has_many :agent_config_states, dependent: :destroy
  has_many :agent_connections, dependent: :destroy
  has_many :execution_runtime_connections, dependent: :destroy
  has_many :execution_runtime_versions, dependent: :destroy
  has_many :user_agent_bindings, dependent: :destroy
  has_many :workspaces, dependent: :destroy

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
