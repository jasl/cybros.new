module IngressAPI
  class BaseController < ActionController::API
    include APIErrorRendering
    include InstallationScopedLookup
  end
end
