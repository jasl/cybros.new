require "test_helper"

module AppSurface
  module Actions
    module Workspaces
      class CreateTest < ActiveSupport::TestCase
        test "creates a private workspace by default" do
          installation = create_installation!
          user = create_user!(installation: installation)

          workspace = Create.call(user: user, name: "Integration Lab")

          assert_equal installation, workspace.installation
          assert_equal user, workspace.user
          assert_equal "Integration Lab", workspace.name
          assert_equal "private", workspace.privacy
          assert_equal false, workspace.is_default
        end

        test "enforces one default workspace per user" do
          installation = create_installation!
          user = create_user!(installation: installation)
          create_workspace!(installation: installation, user: user, is_default: true)

          assert_raises(ActiveRecord::RecordInvalid) do
            Create.call(user: user, name: "Another", is_default: true)
          end
        end
      end
    end
  end
end
