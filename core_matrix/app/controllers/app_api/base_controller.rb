module AppAPI
  # Product-facing API endpoints currently reuse deployment authentication until
  # the user-session API layer exists. Keeping a distinct namespace still lets
  # us separate product read/export surfaces from runtime resource APIs.
  class BaseController < ProgramAPI::BaseController
    rescue_from EmbeddedAgents::Errors::UnauthorizedObservation, with: :render_not_found
    rescue_from EmbeddedAgents::Errors::ClosedObservationSession, with: :render_gone

    private

    def render_gone(_error)
      head :gone
    end
  end
end
