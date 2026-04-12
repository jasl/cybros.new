module AppAPI
  module Admin
    class AuditEntriesController < BaseController
      def index
        render_method_response(
          method_id: "admin_audit_entry_index",
          audit_entries: AppSurface::Queries::Admin::ListAuditEntries.call(
            installation: current_installation
          )
        )
      end
    end
  end
end
