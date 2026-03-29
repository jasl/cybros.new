module LineageStores
  class GarbageCollectJob < ApplicationJob
    queue_as :default

    def perform
      LineageStores::GarbageCollect.call
    end
  end
end
