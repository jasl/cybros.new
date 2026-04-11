module AppAPI
  # Product-facing API endpoints currently reuse agent-snapshot authentication
  # until the user-session API layer exists. Keeping a distinct namespace still
  # lets us separate product read/export surfaces from runtime resource APIs.
  class BaseController < AgentAPI::BaseController
  end
end
