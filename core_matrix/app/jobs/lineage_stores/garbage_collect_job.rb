module LineageStores
  class GarbageCollectJob < ApplicationJob
    queue_as :maintenance

    def perform
      LineageStores::GarbageCollect.call
    end
  end
end
