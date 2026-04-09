module Runtime
  class ManifestsController < ApplicationController
    def show
      base_url = ENV["FENIX_PUBLIC_BASE_URL"].presence || request.base_url

      render json: Fenix::Runtime::Manifest::PairingManifest.call(base_url:)
    end
  end
end
