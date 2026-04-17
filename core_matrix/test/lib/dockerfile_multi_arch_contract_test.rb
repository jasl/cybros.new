require "test_helper"

class DockerfileMultiArchContractTest < ActiveSupport::TestCase
  test "images nexus dockerfile keeps explicit amd64 and arm64 handling" do
    dockerfile = Rails.root.join("../images/nexus/Dockerfile").read

    assert_includes dockerfile, "ARG TARGETARCH"
    assert_includes dockerfile, "amd64"
    assert_includes dockerfile, "arm64"
  end

  test "images nexus dockerfile uses retryable large artifact downloads" do
    dockerfile = Rails.root.join("../images/nexus/Dockerfile").read

    assert_includes dockerfile, "--retry-all-errors"
    assert_includes dockerfile, "--retry 5"
    assert_includes dockerfile, "-C -"
  end

  test "publishable app dockerfiles avoid uname based architecture coupling" do
    dockerfiles = [
      Rails.root.join("../core_matrix/Dockerfile"),
      Rails.root.join("../agents/fenix/Dockerfile"),
      Rails.root.join("../execution_runtimes/nexus/Dockerfile"),
    ]

    dockerfiles.each do |dockerfile|
      assert_not_includes dockerfile.read, "uname -m", "#{dockerfile} should not depend on uname -m"
    end
  end

  test "core matrix dockerfile preserves vendored gem paths before bundle install" do
    dockerfile = Rails.root.join("../core_matrix/Dockerfile").read

    assert_includes dockerfile, "COPY vendor/ ./vendor/"
    assert_not_includes dockerfile, "COPY vendor/* ./vendor/"
  end

  test "images nexus readme documents the buildx multi arch release command" do
    readme = Rails.root.join("../images/nexus/README.md").read

    assert_includes readme, "docker buildx build"
    assert_includes readme, "--platform linux/amd64,linux/arm64"
  end

  test "execution runtime docs require a multi arch nexus base image" do
    readme = Rails.root.join("../execution_runtimes/nexus/README.md").read
    env_sample = Rails.root.join("../execution_runtimes/nexus/env.sample").read

    assert_includes readme, "multi-arch"
    assert_includes env_sample, "multi-arch"
    assert_includes env_sample, "NEXUS_BASE_IMAGE"
  end
end
