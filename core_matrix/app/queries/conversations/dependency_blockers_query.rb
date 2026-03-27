module Conversations
  class DependencyBlockersQuery
    Result = Struct.new(
      :descendant_lineage_blockers,
      :root_store_blocker,
      :variable_provenance_blocker,
      :import_provenance_blocker,
      keyword_init: true
    ) do
      def blocked?
        descendant_lineage_blockers.positive? ||
          root_store_blocker ||
          variable_provenance_blocker ||
          import_provenance_blocker
      end

      def to_h
        {
          descendant_lineage_blockers: descendant_lineage_blockers,
          root_store_blocker: root_store_blocker,
          variable_provenance_blocker: variable_provenance_blocker,
          import_provenance_blocker: import_provenance_blocker,
        }
      end
    end

    def self.call(...)
      new(...).call
    end

    def initialize(conversation:)
      @conversation = conversation
    end

    def call
      Result.new(
        descendant_lineage_blockers: descendant_lineage_blockers,
        root_store_blocker: root_store_blocker?,
        variable_provenance_blocker: variable_provenance_blocker?,
        import_provenance_blocker: import_provenance_blocker?
      )
    end

    private

    def descendant_lineage_blockers
      @conversation.descendant_closures.where.not(descendant_conversation_id: @conversation.id).count
    end

    def root_store_blocker?
      CanonicalStore.where(root_conversation: @conversation).exists?
    end

    def variable_provenance_blocker?
      CanonicalVariable.where(source_conversation: @conversation).exists?
    end

    def import_provenance_blocker?
      ConversationImport.where(source_conversation: @conversation).exists?
    end
  end
end
