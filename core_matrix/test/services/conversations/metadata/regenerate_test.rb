require "test_helper"

class Conversations::Metadata::RegenerateTest < ActiveSupport::TestCase
  test "clears only the targeted field lock before generation" do
    context = fresh_workspace_context!
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])
    conversation.update!(
      title: "Pinned title",
      title_source: "user",
      title_lock_state: "user_locked",
      summary: "Pinned summary",
      summary_source: "user",
      summary_lock_state: "user_locked"
    )

    observed = {}
    occurred_at = Time.zone.parse("2026-04-06 11:15:00")
    generator = lambda do |conversation:, field:, occurred_at:|
      current = conversation.reload
      observed[:field] = field
      observed[:title_lock_state] = current.title_lock_state
      observed[:summary_lock_state] = current.summary_lock_state

      current.update!(
        title: "Generated title",
        title_source: "generated",
        title_updated_at: occurred_at
      )
    end

    Conversations::Metadata::Regenerate.call(
      conversation: conversation,
      field: :title,
      generator: generator,
      occurred_at: occurred_at
    )

    assert_equal "title", observed[:field]
    assert_equal "unlocked", observed[:title_lock_state]
    assert_equal "user_locked", observed[:summary_lock_state]

    conversation.reload
    assert_equal "Generated title", conversation.title
    assert_equal "generated", conversation.title_source
    assert_equal "unlocked", conversation.title_lock_state
    assert_equal "Pinned summary", conversation.summary
    assert_equal "user_locked", conversation.summary_lock_state
  end

  private

  def fresh_workspace_context!
    Installation.destroy_all
    create_workspace_context!
  end
end
