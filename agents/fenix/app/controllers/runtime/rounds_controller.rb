module Runtime
  class RoundsController < ApplicationController
    def prepare
      render json: Fenix::Runtime::PrepareRound.call(payload: request_payload)
    end

    private

    def request_payload
      params.to_unsafe_h.except("controller", "action")
    end
  end
end
