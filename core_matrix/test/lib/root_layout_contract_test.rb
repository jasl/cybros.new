require "test_helper"

class RootLayoutContractTest < ActiveSupport::TestCase
  test "agents doc registers execution_runtimes/nexus as the active runtime project" do
    agents_doc = Rails.root.join("../AGENTS.md").read

    assert_includes agents_doc, "- `agents/fenix`: active cowork Ruby on Rails application"
    assert_includes agents_doc, "- `execution_runtimes/nexus`: active Nexus execution runtime gem"
    refute_includes agents_doc, "execution_runtimes/nexus.old"
  end

  test "agents doc lists gem-based nexus verification and packaged smoke commands" do
    agents_doc = Rails.root.join("../AGENTS.md").read

    assert_includes agents_doc, "### `agents/fenix`"
    assert_includes agents_doc, "bin/brakeman --no-pager"
    assert_includes agents_doc, "bin/rails db:test:prepare"
    assert_includes agents_doc, "### `execution_runtimes/nexus`"
    assert_includes agents_doc, "bundle exec rake test"
    assert_includes agents_doc, "bundle exec rubocop"
    assert_includes agents_doc, "bundle exec gem build cybros_nexus.gemspec"
    assert_includes agents_doc, "nexus --help"
    assert_includes agents_doc, "nexus run --help"
  end

  test "root ci detects execution_runtimes/nexus changes and runs a dedicated gem verification job" do
    workflow = Rails.root.join("../.github/workflows/ci.yml").read
    nexus_job = workflow[/  execution_runtime_nexus_verify:[\s\S]*?(?=\n\n  [a-z_]+:|\z)/]

    assert_includes workflow, "execution_runtime_nexus: ${{ steps.detect.outputs.execution_runtime_nexus }}"
    assert_includes workflow, "execution_runtime_nexus=false"
    assert_includes workflow, "execution_runtime_nexus=true"
    assert_includes workflow, "execution_runtimes/nexus/*)"
    assert_includes workflow, "jobs:"
    assert_includes nexus_job, "execution_runtime_nexus_verify:"
    assert_includes nexus_job, "name: execution_runtimes/nexus / verify"
    assert_includes nexus_job, "working-directory: execution_runtimes/nexus"
    assert_includes nexus_job, "bundle exec rake test"
    assert_includes nexus_job, "bundle exec rubocop"
    assert_includes nexus_job, "bundle exec gem build cybros_nexus.gemspec"
    assert_includes nexus_job, "nexus run --help"
    refute_includes nexus_job, "bin/rails db:test:prepare"
  end

  test "fenix readme identifies nexus as the runtime boundary" do
    readme = Rails.root.join("../agents/fenix/README.md").read

    assert_includes readme, "active cowork app"
    assert_includes readme, "`execution_runtimes/nexus`"
    assert_includes readme, "bin/brakeman --no-pager"
    assert_includes readme, "bin/bundler-audit"
    assert_includes readme, "bin/rubocop -f github"
    assert_includes readme, "bin/rails db:test:prepare"
    assert_includes readme, "bin/rails test"
  end

  test "nexus readme documents operator env, state, and packaged smoke flow" do
    readme = Rails.root.join("../execution_runtimes/nexus/README.md").read

    assert_includes readme, "nexus run"
    assert_includes readme, "./exe/nexus run"
    assert_includes readme, "CORE_MATRIX_BASE_URL"
    assert_includes readme, "NEXUS_HOME_ROOT"
    assert_includes readme, "state.sqlite3"
    assert_includes readme, "GEM_HOME"
    assert_includes readme, "nexus --help"
    assert_includes readme, "nexus run --help"
  end
end
