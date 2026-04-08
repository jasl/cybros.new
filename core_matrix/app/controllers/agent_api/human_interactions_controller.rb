module AgentAPI
  class HumanInteractionsController < BaseController
    def create
      workflow_node = find_workflow_node!(request_payload.fetch("workflow_node_id"))
      request = HumanInteractions::Request.call(
        request_type: request_payload.fetch("request_type"),
        workflow_node: workflow_node,
        blocking: request_payload.fetch("blocking", true),
        request_payload: request_payload.fetch("request_payload", {})
      )

      render json: {
        method_id: "human_interactions_request",
      }.merge(serialize_human_interaction_request(request)), status: :created
    end
  end
end
