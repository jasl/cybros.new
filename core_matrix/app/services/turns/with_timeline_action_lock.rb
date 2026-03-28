module Turns
  class WithTimelineActionLock
    def self.call(*args, **kwargs, &block)
      new(*args, **kwargs).call(&block)
    end

    def initialize(turn:, before_phrase:, action_phrase:)
      @turn = turn
      @before_phrase = before_phrase
      @action_phrase = action_phrase
    end

    def call
      Turns::WithTimelineMutationLock.call(
        turn: @turn,
        retained_message: "must be retained before #{@before_phrase}",
        active_message: "must belong to an active conversation to #{@action_phrase}",
        closing_message: "must not #{@action_phrase} while close is in progress",
        interrupted_message: "must not #{@action_phrase} after turn interruption"
      ) do |turn|
        yield turn
      end
    end
  end
end
