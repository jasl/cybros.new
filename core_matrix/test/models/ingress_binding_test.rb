require "test_helper"

class IngressBindingTest < ActiveSupport::TestCase
  test "generates a public id and a unique public ingress id" do
    context = create_workspace_context!

    binding_one = create_ingress_binding!(context)
    binding_two = create_ingress_binding!(context)

    assert binding_one.public_id.present?
    assert_equal binding_one, IngressBinding.find_by_public_id!(binding_one.public_id)
    assert binding_one.public_ingress_id.present?
    assert_not_equal binding_one.public_ingress_id, binding_two.public_ingress_id
  end

  test "belongs to a mounted workspace agent and optional default execution runtime" do
    context = create_workspace_context!

    binding = IngressBinding.new(
      installation: context[:installation],
      workspace_agent: context[:workspace_agent],
      default_execution_runtime: context[:execution_runtime],
      routing_policy_payload: {},
      manual_entry_policy: {
        "allow_app_entry" => true,
        "allow_external_entry" => true,
      }
    )

    assert_equal :belongs_to, IngressBinding.reflect_on_association(:workspace_agent)&.macro
    assert_equal :belongs_to, IngressBinding.reflect_on_association(:default_execution_runtime)&.macro
    assert binding.valid?, binding.errors.full_messages.to_sentence
  end

  test "stores ingress secrets by digest instead of plaintext" do
    context = create_workspace_context!
    plaintext_secret, digest = IngressBinding.issue_ingress_secret

    binding = IngressBinding.create!(
      installation: context[:installation],
      workspace_agent: context[:workspace_agent],
      default_execution_runtime: context[:execution_runtime],
      ingress_secret_digest: digest,
      routing_policy_payload: {},
      manual_entry_policy: {
        "allow_app_entry" => true,
        "allow_external_entry" => true,
      }
    )

    assert_not_equal plaintext_secret, binding.ingress_secret_digest
    assert_equal digest, binding.ingress_secret_digest
    assert binding.matches_ingress_secret?(plaintext_secret)
  end

  test "rejects a workspace agent from a different installation" do
    context = create_workspace_context!
    foreign_workspace_agent = context[:workspace_agent].dup
    foreign_workspace_agent.installation_id = context[:installation].id + 1_000

    binding = IngressBinding.new(
      installation: context[:installation],
      workspace_agent: foreign_workspace_agent,
      default_execution_runtime: context[:execution_runtime],
      routing_policy_payload: {},
      manual_entry_policy: {
        "allow_app_entry" => true,
        "allow_external_entry" => true,
      }
    )

    assert_not binding.valid?
    assert_includes binding.errors[:workspace_agent], "must belong to the same installation"
  end

  private

  def create_ingress_binding!(context, **attrs)
    IngressBinding.create!({
      installation: context[:installation],
      workspace_agent: context[:workspace_agent],
      default_execution_runtime: context[:execution_runtime],
      routing_policy_payload: {},
      manual_entry_policy: {
        "allow_app_entry" => true,
        "allow_external_entry" => true,
      },
    }.merge(attrs))
  end
end
