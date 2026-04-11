class RuntimeManifestsController < ApplicationController
  def show
    base_url = ENV["FENIX_PUBLIC_BASE_URL"].presence || request.base_url

    render json: Runtime::Manifest::PairingManifest.call(base_url:)
  end
end
