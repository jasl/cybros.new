module HasPublicId
  extend ActiveSupport::Concern

  included do
    validates :public_id, uniqueness: true, allow_nil: true
  end

  class_methods do
    def find_by_public_id!(public_id)
      find_by!(public_id: public_id)
    end
  end
end
