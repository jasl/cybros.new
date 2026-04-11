module Nexus
  module Shared
    module Values
      class MailboxDeliveryTracker
        MAX_TRACKED_DELIVERIES = 10_000

        class << self
          def claim(mailbox_item_id:, delivery_no:)
            tracker.claim(mailbox_item_id:, delivery_no:)
          end

          def reset!
            tracker.reset!
          end

          private

          def tracker
            @tracker ||= new
          end
        end

        def initialize
          @claims = {}
          @mutex = Mutex.new
        end

        def claim(mailbox_item_id:, delivery_no:)
          mailbox_item_id = mailbox_item_id.to_s
          delivery_no = delivery_no.to_i

          @mutex.synchronize do
            current = @claims[mailbox_item_id]
            return false if current.present? && current >= delivery_no

            @claims.delete(mailbox_item_id)
            @claims[mailbox_item_id] = delivery_no
            prune_if_needed!
            true
          end
        end

        def reset!
          @mutex.synchronize { @claims = {} }
        end

        private

        def prune_if_needed!
          @claims.shift while @claims.size > MAX_TRACKED_DELIVERIES
        end
      end
    end
  end
end
