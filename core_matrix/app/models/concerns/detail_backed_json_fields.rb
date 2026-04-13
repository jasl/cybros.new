module DetailBackedJsonFields
  extend ActiveSupport::Concern

  class_methods do
    def detail_backed_json_fields(association_name, *field_names)
      field_names.each do |field_name|
        define_method(field_name) do
          public_send(association_name)&.public_send(field_name) || {}
        end

        define_method("#{field_name}=") do |value|
          normalized_value = normalize_detail_backed_json_field_value(value)
          detail_record = public_send(association_name)
          detail_record ||= public_send("build_#{association_name}")
          detail_record.public_send("#{field_name}=", normalized_value)
        end
      end
    end
  end

  private

  def detail_backed_json_validation_required?(association_name)
    return true if new_record?

    association_proxy = association(association_name)
    return true if association_proxy.loaded? && association_proxy.target&.changed?

    false
  end

  def normalize_detail_backed_json_field_value(value)
    value = {} if value.nil?
    return value.deep_stringify_keys if value.is_a?(Hash)

    value
  end
end
