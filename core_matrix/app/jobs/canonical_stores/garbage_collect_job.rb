module CanonicalStores
  class GarbageCollectJob < ApplicationJob
    queue_as :default

    def perform
      CanonicalStores::GarbageCollect.call
    end
  end
end
