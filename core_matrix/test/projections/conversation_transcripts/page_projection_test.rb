require "test_helper"

module ConversationTranscripts
end

class ConversationTranscripts::PageProjectionTest < ActiveSupport::TestCase
  test "uses the page projection owner and removes the legacy list query" do
    assert page_projection_class.present?, "ConversationTranscripts::PageProjection must exist"
    refute ConversationTranscripts.constants.include?(legacy_list_query_constant_name)
  end

  test "returns the canonical visible transcript with cursor pagination" do
    context = build_canonical_variable_context!
    first_turn = context[:turn]
    first_output = attach_selected_output!(first_turn, content: "First answer")
    second_turn = Turns::StartUserTurn.call(
      conversation: context[:conversation],
      content: "Second question",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    second_output = attach_selected_output!(second_turn, content: "Second answer")
    ConversationMessageVisibility.create!(
      installation: context[:installation],
      conversation: context[:conversation],
      message: first_output,
      hidden: true,
      excluded_from_context: false
    )

    first_page = page_projection_class.call(
      conversation: context[:conversation],
      limit: 2
    )

    assert_equal(
      [first_turn.selected_input_message, second_turn.selected_input_message],
      first_page.messages
    )
    assert_equal second_turn.selected_input_message.public_id, first_page.next_cursor

    second_page = page_projection_class.call(
      conversation: context[:conversation],
      cursor: first_page.next_cursor,
      limit: 2
    )

    assert_equal [second_output], second_page.messages
    assert_nil second_page.next_cursor
  end

  private

  def legacy_list_query_constant_name
    %i[List Query].join.to_sym
  end

  def page_projection_class
    @page_projection_class ||= ConversationTranscripts.const_get(:PageProjection, false)
  rescue NameError
    flunk "ConversationTranscripts::PageProjection must exist"
  end
end
