module AppSurface
  class MethodResponse
    def self.call(method_id:, **payload)
      payload.deep_stringify_keys.compact.merge("method_id" => method_id.to_s)
    end
  end
end
