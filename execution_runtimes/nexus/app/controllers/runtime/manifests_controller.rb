module Runtime
  class ManifestsController < ApplicationController
    def show
      base_url = ENV["NEXUS_PUBLIC_BASE_URL"].presence || request.base_url

      render json: Nexus::Runtime::Manifest::PairingManifest.call(base_url:)
    end
  end
end
