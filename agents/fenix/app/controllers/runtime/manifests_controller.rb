module Runtime
  class ManifestsController < ApplicationController
    def show
      base_url = ENV.fetch("FENIX_PUBLIC_BASE_URL", request.base_url)

      render json: Fenix::Runtime::PairingManifest.call(base_url:)
    end
  end
end
