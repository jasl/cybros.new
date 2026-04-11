module ResourceVisibility
  class Usability
    def self.call(...)
      new(...).call
    end

    def self.agent_usable_by_user?(...)
      new(...).agent_usable?
    end

    def self.execution_runtime_usable_by_user?(...)
      new(...).execution_runtime_usable?
    end

    def self.workspace_accessible_by_user?(...)
      new(...).workspace_accessible?
    end

    def self.conversation_accessible_by_user?(...)
      new(...).conversation_accessible?
    end

    def initialize(user:, agent: nil, execution_runtime: nil, workspace: nil, conversation: nil)
      @user = user
      @agent = agent
      @execution_runtime = execution_runtime
      @workspace = workspace
      @conversation = conversation
    end

    def call
      return conversation_accessible? if @conversation.present?
      return workspace_accessible? if @workspace.present?
      return execution_runtime_usable? if @execution_runtime.present?

      agent_usable?
    end

    def agent_usable?
      usable_record?(@agent)
    end

    def execution_runtime_usable?
      usable_record?(@execution_runtime)
    end

    def workspace_accessible?
      workspace = fresh_record(@workspace)
      return false if @user.blank? || workspace.blank?
      return false unless workspace.installation_id == @user.installation_id
      return false unless workspace.user_id == @user.id

      binding = fresh_record(workspace.user_agent_binding)
      return false if binding.blank?
      return false unless binding.installation_id == @user.installation_id
      return false unless binding.user_id == @user.id

      agent = fresh_record(binding.agent)
      usable_record?(agent)
    end

    def conversation_accessible?
      conversation = @conversation
      return false if conversation.blank?
      return false unless workspace_accessible_for?(conversation.workspace)

      usable_record?(fresh_record(conversation.agent))
    end

    private

    def workspace_accessible_for?(workspace)
      self.class.workspace_accessible_by_user?(user: @user, workspace: workspace)
    end

    def usable_record?(record)
      record = fresh_record(record)
      return true if record.blank?
      return false if @user.blank?
      return false unless record.respond_to?(:installation_id) && record.installation_id == @user.installation_id
      return false unless record.respond_to?(:lifecycle_state) && record.lifecycle_state == "active"

      if record.respond_to?(:visibility_public?) && record.visibility_public?
        return true
      end

      record.respond_to?(:visibility_private?) &&
        record.visibility_private? &&
        record.respond_to?(:owner_user_id) &&
        record.owner_user_id == @user.id
    end

    def fresh_record(record)
      return record if record.blank?
      return record unless record.class < ApplicationRecord
      return record unless record.id.present?

      record.class.find_by(id: record.id)
    end
  end
end
