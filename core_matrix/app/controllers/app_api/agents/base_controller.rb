module AppAPI
  module Agents
    class BaseController < AppAPI::BaseController
      before_action :set_agent

      private

      def set_agent
        @agent ||= find_agent!(params.fetch(:agent_id))
      end
    end
  end
end
