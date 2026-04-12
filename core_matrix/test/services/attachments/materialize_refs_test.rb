require "test_helper"

class Attachments::MaterializeRefsTest < ActiveSupport::TestCase
  test "materializes reusable attachment refs into new logical attachment rows" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
    )
    source_turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Source input",
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    source_message = source_turn.selected_input_message
    source_attachment = create_message_attachment!(
      message: source_message,
      filename: "source.txt",
      body: "source attachment"
    )
    target_turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Target input",
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    target_message = target_turn.selected_input_message

    materialized = Attachments::MaterializeRefs.call(
      message: target_message,
      refs: [source_attachment]
    )

    assert_equal 1, materialized.size

    attachment = materialized.first
    assert_not_equal source_attachment.id, attachment.id
    assert_equal target_message, attachment.message
    assert_equal target_message.conversation, attachment.conversation
    assert_equal source_attachment, attachment.origin_attachment
    assert_equal source_message, attachment.origin_message
    assert attachment.file.attached?
    assert_equal "source.txt", attachment.file.filename.to_s
    assert_equal source_attachment.file.download, attachment.file.download
  end

  test "streams source files without eagerly downloading the full blob" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
    )
    source_turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Source input",
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    source_attachment = create_message_attachment!(
      message: source_turn.selected_input_message,
      filename: "source.txt",
      body: "source attachment"
    )
    target_turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Target input",
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    source_blob = source_attachment.file.blob
    source_blob.singleton_class.alias_method(:__original_download_for_test, :download)
    source_blob.singleton_class.define_method(:download) do |*|
      raise "download should not be called"
    end

    begin
      materialized = Attachments::MaterializeRefs.call(
        message: target_turn.selected_input_message,
        refs: [source_attachment]
      )

      assert_equal 1, materialized.size
      assert_equal "source attachment", materialized.first.file.download
    ensure
      source_blob.singleton_class.alias_method(:download, :__original_download_for_test)
      source_blob.singleton_class.remove_method(:__original_download_for_test)
    end
  end

  test "rejects refs that are not message attachments" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Target input",
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    assert_raises(ArgumentError) do
      Attachments::MaterializeRefs.call(
        message: turn.selected_input_message,
        refs: [turn.selected_input_message]
      )
    end
  end
end
