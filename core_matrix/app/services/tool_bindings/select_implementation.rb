module ToolBindings
  class SelectImplementation
    def self.call(...)
      new(...).call
    end

    def initialize(tool_definition:, preferred_implementation: nil)
      @tool_definition = tool_definition
      @preferred_implementation = preferred_implementation
    end

    def call
      selected = @preferred_implementation || @tool_definition.default_implementation
      validate_selection!(selected)
      selected
    end

    private

    def validate_selection!(selected)
      return if selected == @tool_definition.default_implementation

      raise_invalid!("must use the reserved implementation") if @tool_definition.reserved?
      raise_invalid!("must use the approved implementation") if @tool_definition.whitelist_only?
      raise_invalid!("must belong to the tool definition") unless selected.tool_definition_id == @tool_definition.id
    end

    def raise_invalid!(message)
      record = ToolBinding.new(tool_definition: @tool_definition, tool_implementation: @preferred_implementation, binding_payload: {})
      record.errors.add(:tool_definition, message)
      raise ActiveRecord::RecordInvalid, record
    end
  end
end
