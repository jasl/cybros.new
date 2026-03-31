module ProviderExecution
  class AppendToolResult
    def self.call(...)
      new(...).call
    end

    def initialize(tool_call:, routed_result:)
      @tool_call = tool_call.deep_stringify_keys
      @routed_result = routed_result
    end

    def call
      {
        "tool_call_id" => @tool_call.fetch("call_id"),
        "call_id" => @tool_call.fetch("call_id"),
        "tool_name" => @tool_call.fetch("tool_name"),
        "arguments" => @tool_call.fetch("arguments", {}),
        "provider_format" => @tool_call["provider_format"],
        "provider_item_id" => @tool_call["provider_item_id"],
        "result" => @routed_result.result,
      }
    end
  end
end
