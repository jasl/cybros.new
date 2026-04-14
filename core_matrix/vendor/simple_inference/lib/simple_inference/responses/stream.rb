# frozen_string_literal: true

module SimpleInference
  module Responses
    module Events
      class Base
        attr_reader :type, :raw, :snapshot

        def initialize(type:, raw: nil, snapshot: nil)
          @type = type
          @raw = raw
          @snapshot = snapshot
        end
      end

      class Raw < Base
        def initialize(type:, raw:, snapshot: nil)
          super(type: type, raw: raw, snapshot: snapshot)
        end
      end

      class TextDelta < Base
        attr_reader :delta

        def initialize(delta:, raw: nil, snapshot: nil)
          @delta = delta.to_s
          super(type: "response.output_text.delta", raw: raw, snapshot: snapshot)
        end
      end

      class Completed < Base
        attr_reader :result

        def initialize(result:, raw: nil)
          @result = result
          super(type: "response.completed", raw: raw, snapshot: result)
        end
      end
    end

    class Stream
      include Enumerable

      def initialize(&producer)
        @producer = producer
        @started = false
        @text = +""
        @final_result = nil
      end

      def each
        return enum_for(:each) unless block_given?
        raise SimpleInference::ConfigurationError, "Responses::Stream can only be consumed once" if @started

        @started = true
        @final_result =
          @producer.call do |event|
            if event.is_a?(Events::TextDelta)
              @text << event.delta
            elsif event.is_a?(Events::Completed)
              @final_result = event.result
            end

            yield event
          end
      end

      def text
        get_output_text
      end

      def get_output_text
        until_done
        return @final_result.output_text if @final_result

        @text.dup
      end

      def get_final_result
        until_done
      end

      def until_done
        each { |_event| nil } unless @started
        @final_result
      end

      def close
        nil
      end
    end
  end
end
