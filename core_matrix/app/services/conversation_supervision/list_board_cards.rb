module ConversationSupervision
  class ListBoardCards
    LANE_ORDER = ConversationSupervisionState::BOARD_LANES.freeze

    def self.call(...)
      new(...).call
    end

    def initialize(installation:, board_lane: nil)
      @installation = installation
      @board_lane = board_lane
    end

    def call
      states = ConversationSupervisionState.where(installation: @installation)
      states = states.where(board_lane: @board_lane) if @board_lane.present?

      states.to_a
        .sort_by { |state| [lane_rank(state.board_lane), -(state.last_progress_at || Time.at(0)).to_f, state.public_id] }
        .map { |state| ConversationSupervision::BuildBoardCard.call(conversation_supervision_state: state) }
    end

    private

    def lane_rank(board_lane)
      LANE_ORDER.index(board_lane) || LANE_ORDER.length
    end
  end
end
