require "json"

module Processes
  class ProxyRegistry
  class << self
    def default
      @default ||= new(routes_path: default_routes_path)
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

    def reset_default!
      @default = nil
    end

    private

    def default_routes_path
      ENV.fetch("NEXUS_DEV_PROXY_ROUTES_FILE", Rails.root.join("tmp", "dev-proxy", "routes.caddy").to_s)
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

    with_entries do |entries|
      entries[process_run_id] = entry
    end
    entry
  end

  def lookup(process_run_id:)
    with_entries do |entries|
      entries[process_run_id]
    end
  end

  def unregister(process_run_id:)
    with_entries do |entries|
      entries.delete(process_run_id)
    end
  end

  def reset!
    with_entries do |entries|
      entries.clear
    end
  end

  private

  def with_entries
    @state_path.dirname.mkpath
    @routes_path.dirname.mkpath

    File.open(@state_path, File::RDWR | File::CREAT, 0o644) do |state_file|
      state_file.flock(File::LOCK_EX)
      entries = load_entries_from(state_file)
      result = yield(entries)
      persist_entries(state_file, entries)
      result
    ensure
      state_file.flock(File::LOCK_UN)
    end
  end

  def load_entries_from(state_file)
    state_file.rewind
    raw = state_file.read
    return {} if raw.blank?

    JSON.parse(raw)
  rescue JSON::ParserError
    {}
  end

  def persist_entries(state_file, entries)
    state_file.rewind
    state_file.truncate(0)
    state_file.write(JSON.pretty_generate(entries))
    state_file.flush
    @routes_path.write(render_routes(entries))
  end

  def render_routes(entries)
    return "# managed by Processes::ProxyRegistry\n" if entries.empty?

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
