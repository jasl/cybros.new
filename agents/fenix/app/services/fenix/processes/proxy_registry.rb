require "json"

module Fenix
  module Processes
    class ProxyRegistry
      class << self
        def default
          @default ||= new
        end

        def register(...)
          default.register(...)
        end

        def lookup(...)
          default.lookup(...)
        end

        def unregister(...)
          default.unregister(...)
        end

        def reset!
          default.reset!
        end
      end

      def initialize(routes_path: Rails.root.join("tmp", "dev-proxy", "routes.caddy"), state_path: nil)
        @routes_path = Pathname(routes_path)
        @state_path = Pathname(state_path || @routes_path.sub_ext(".json"))
      end

      def register(process_run_id:, target_port:)
        entry = {
          "process_run_id" => process_run_id,
          "path_prefix" => "/dev/#{process_run_id}",
          "target_port" => Integer(target_port),
          "target_url" => "http://127.0.0.1:#{Integer(target_port)}",
        }

        entries = load_entries
        entries[process_run_id] = entry
        persist_entries(entries)
        entry
      end

      def lookup(process_run_id:)
        load_entries[process_run_id]
      end

      def unregister(process_run_id:)
        entries = load_entries
        entry = entries.delete(process_run_id)
        persist_entries(entries)
        entry
      end

      def reset!
        persist_entries({})
      end

      private

      def load_entries
        return {} unless @state_path.exist?

        JSON.parse(@state_path.read)
      rescue JSON::ParserError
        {}
      end

      def persist_entries(entries)
        @state_path.dirname.mkpath
        @routes_path.dirname.mkpath
        @state_path.write(JSON.pretty_generate(entries))
        @routes_path.write(render_routes(entries))
      end

      def render_routes(entries)
        return "# managed by Fenix::Processes::ProxyRegistry\n" if entries.empty?

        entries
          .values
          .sort_by { |entry| entry.fetch("process_run_id") }
          .map do |entry|
            <<~CADDY
              handle_path #{entry.fetch("path_prefix")}/* {
                reverse_proxy 127.0.0.1:#{entry.fetch("target_port")}
              }
            CADDY
          end
          .join("\n")
      end
    end
  end
end
