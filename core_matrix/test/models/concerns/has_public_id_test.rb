require "test_helper"

class HasPublicIdTest < ActiveSupport::TestCase
  setup do
    ActiveRecord::Base.connection_pool.with_connection do |connection|
      connection.drop_table(:public_id_test_records, if_exists: true)
      connection.create_table :public_id_test_records do |t|
        t.uuid :public_id, null: false, default: -> { "uuidv7()" }
        t.timestamps
      end
      connection.add_index :public_id_test_records, :public_id, unique: true
    end

    self.class.const_set(:PublicIdTestRecord, Class.new(ApplicationRecord)) unless self.class.const_defined?(:PublicIdTestRecord, false)
    @model_class = self.class.const_get(:PublicIdTestRecord)
    @model_class.class_eval do
      self.table_name = "public_id_test_records"
      include HasPublicId
    end
  end

  teardown do
    ActiveRecord::Base.connection_pool.with_connection do |connection|
      connection.drop_table(:public_id_test_records, if_exists: true)
    end
  end

  test "generates and resolves public ids" do
    record = @model_class.create!

    assert record.public_id.present?
    assert_equal record, @model_class.find_by_public_id!(record.public_id)
  end
end
