module Runtime
  class ManifestsController < ApplicationController
    def show
      render json: Fenix::Runtime::PairingManifest.call(base_url: request.base_url)
    end
  end
end
