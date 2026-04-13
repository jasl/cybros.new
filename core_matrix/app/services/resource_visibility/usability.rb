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
      accessible_record?(@agent, Agent.visible_to_user(@user))
    end

    def execution_runtime_usable?
      accessible_record?(@execution_runtime, ExecutionRuntime.visible_to_user(@user))
    end

    def workspace_accessible?
      accessible_record?(@workspace, Workspace.accessible_to_user(@user))
    end

    def conversation_accessible?
      accessible_record?(@conversation, Conversation.accessible_to_user(@user))
    end

    private

    def accessible_record?(record, relation)
      record = fresh_record(record)
      return true if record.blank?
      return false if @user.blank?
      return false unless relation.present?

      if record.is_a?(ApplicationRecord) && record.id.present?
        return relation.where(id: record.id).exists?
      end

      return relation.where(public_id: record.public_id).exists? if record.respond_to?(:public_id) && record.public_id.present?

      false
    end

    def fresh_record(record)
      return record if record.blank?
      return record unless record.class < ApplicationRecord
      return record unless record.id.present?

      record.class.find_by(id: record.id)
    end
  end
end
