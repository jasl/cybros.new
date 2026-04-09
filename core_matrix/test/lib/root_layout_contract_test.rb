require "test_helper"

class RootLayoutContractTest < ActiveSupport::TestCase
  test "agents doc registers the active fenix project plus nexus" do
    agents_doc = Rails.root.join("../AGENTS.md").read

    assert_includes agents_doc, "- `agents/fenix`: active cowork Ruby on Rails application"
    assert_includes agents_doc, "- `images/nexus`: Docker runtime base project for cowork agents"
  end

  test "agents doc lists verification commands for fenix and nexus" do
    agents_doc = Rails.root.join("../AGENTS.md").read

    assert_includes agents_doc, "### `agents/fenix`"
    assert_includes agents_doc, "bin/brakeman --no-pager"
    assert_includes agents_doc, "bin/rails db:test:prepare"
    assert_includes agents_doc, "### `images/nexus`"
    assert_includes agents_doc, "docker build -f images/nexus/Dockerfile -t nexus-local ."
    assert_includes agents_doc, "/workspace/images/nexus/verify.sh"
  end

  test "root ci detects nexus changes and runs a dedicated nexus verification job" do
    workflow = Rails.root.join("../.github/workflows/ci.yml").read

    assert_includes workflow, "images_nexus: ${{ steps.detect.outputs.images_nexus }}"
    assert_includes workflow, "images_nexus=false"
    assert_includes workflow, "images_nexus=true"
    assert_includes workflow, "images/nexus/*)"
    assert_includes workflow, "jobs:"
    assert_includes workflow, "images_nexus_verify:"
    assert_includes workflow, "name: images/nexus / verify"
    assert_includes workflow, "docker build -f images/nexus/Dockerfile -t nexus-local ."
    assert_includes workflow, "/workspace/images/nexus/verify.sh"
  end

  test "fenix readme identifies the active cowork app and its verification commands" do
    readme = Rails.root.join("../agents/fenix/README.md").read

    assert_includes readme, "active cowork app"
    assert_includes readme, "`images/nexus`"
    assert_includes readme, "bin/brakeman --no-pager"
    assert_includes readme, "bin/bundler-audit"
    assert_includes readme, "bin/rubocop -f github"
    assert_includes readme, "bin/rails db:test:prepare"
    assert_includes readme, "bin/rails test"
  end

  test "nexus readme documents the root-context build and verification flow" do
    readme = Rails.root.join("../images/nexus/README.md").read

    assert_includes readme, "`agents/fenix`"
    assert_includes readme, "docker build -f images/nexus/Dockerfile -t nexus-local ."
    assert_includes readme, "/workspace/images/nexus/verify.sh"
    assert_includes readme, "Task 9 verification"
  end
end
