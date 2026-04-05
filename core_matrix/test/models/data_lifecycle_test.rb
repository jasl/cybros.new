require "test_helper"

class DataLifecycleTest < ActiveSupport::TestCase
  test "exposes the supported lifecycle classes" do
    assert_equal %i[
      owner_bound
      reference_owned
      shared_frozen_contract
      recomputable
      ephemeral_observability
      bounded_audit
      retained_aggregate
    ], DataLifecycle::LIFECYCLE_CLASSES
  end

  test "declares representative lifecycle classes on key models" do
    expected = {
      Conversation => :owner_bound,
      Message => :owner_bound,
      ConversationImport => :owner_bound,
      ConversationSummarySegment => :owner_bound,
      ConversationEvent => :owner_bound,
      WorkflowNodeEvent => :owner_bound,
      JsonDocument => :reference_owned,
      ExecutionContract => :shared_frozen_contract,
      ExecutionCapabilitySnapshot => :shared_frozen_contract,
      ExecutionContextSnapshot => :shared_frozen_contract,
      ConversationDiagnosticsSnapshot => :recomputable,
      TurnDiagnosticsSnapshot => :recomputable,
      ConversationSupervisionSession => :ephemeral_observability,
      ConversationSupervisionSnapshot => :ephemeral_observability,
      ConversationSupervisionMessage => :ephemeral_observability,
      ConversationSupervisionState => :recomputable,
      ConversationCapabilityPolicy => :owner_bound,
      ConversationCapabilityGrant => :owner_bound,
      ConversationControlRequest => :bounded_audit,
      ConversationExportRequest => :ephemeral_observability,
      ConversationDebugExportRequest => :ephemeral_observability,
      UsageEvent => :bounded_audit,
      UsageRollup => :retained_aggregate,
    }

    expected.each do |model_class, lifecycle_class|
      assert_equal lifecycle_class, model_class.data_lifecycle_kind, "#{model_class.name} lifecycle kind"
    end
  end

  test "rejects unsupported lifecycle classes" do
    error = assert_raises(ArgumentError) do
      Class.new(ApplicationRecord) do
        include DataLifecycle

        data_lifecycle_kind! :sti
      end
    end

    assert_equal "unsupported data lifecycle class :sti", error.message
  end
end
