require "test_helper"

module AppSurface
  module Presenters
  end
end

class AppSurface::Presenters::WorkspacePresenterTest < ActiveSupport::TestCase
  test "emits only public ids and stable workspace fields" do
    context = create_workspace_context!
    payload = AppSurface::Presenters::WorkspacePresenter.call(workspace: context[:workspace])

    assert_equal context[:workspace].public_id, payload.fetch("workspace_id")
    assert_equal context[:agent].public_id, payload.fetch("agent_id")
    assert_equal context[:execution_runtime].public_id, payload.fetch("default_execution_runtime_id")
    assert_equal context[:workspace].name, payload.fetch("name")
    assert_equal context[:workspace].privacy, payload.fetch("privacy")
    assert_equal context[:workspace].is_default, payload.fetch("is_default")
    refute_includes payload.to_json, %("#{context[:workspace].id}")
  end

  test "uses an explicit agent public id without querying the workspace agent association" do
    context = create_workspace_context!
    context[:workspace].association(:agent).reset

    queries = capture_sql_queries do
      payload = AppSurface::Presenters::WorkspacePresenter.call(
        workspace: context[:workspace],
        agent_public_id: context[:agent].public_id
      )

      assert_equal context[:agent].public_id, payload.fetch("agent_id")
    end

    assert queries.none? { |sql| sql.include?("\"agents\"") }, "expected presenter to avoid agent lookups, got:\n#{queries.join("\n\n")}"
  end
end
