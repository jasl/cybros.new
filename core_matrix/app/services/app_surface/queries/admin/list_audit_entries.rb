module AppSurface
  module Queries
    module Admin
      class ListAuditEntries
        def self.call(...)
          new(...).call
        end

        def initialize(installation:, limit: 50)
          @installation = installation
          @limit = limit
        end

        def call
          AuditLog
            .where(installation: @installation, actor_type: "User")
            .order(created_at: :desc, id: :desc)
            .limit(@limit)
            .includes(:actor, :subject)
            .map { |audit_entry| AppSurface::Presenters::AuditEntryPresenter.call(audit_entry: audit_entry) }
        end
      end
    end
  end
end
