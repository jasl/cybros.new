module AppAPI
  module Workspaces
    class BaseController < AppAPI::BaseController
      before_action :set_workspace

      private

      def set_workspace
        @workspace ||= find_workspace!(params.fetch(:workspace_id))
      end
    end
  end
end
