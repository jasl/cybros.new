module CybrosNexus
  Config = Data.define(
    :home_root,
    :state_path,
    :memory_root,
    :skills_root,
    :logs_root,
    :tmp_root,
    :core_matrix_base_url,
    :public_base_url,
    :http_bind,
    :http_port
  ) do
    def self.load(env: ENV, home_dir: Dir.home)
      http_bind = env.fetch("NEXUS_HTTP_BIND", "127.0.0.1")
      http_port = Integer(env.fetch("NEXUS_HTTP_PORT", 4040))
      home_root = expand_root(env.fetch("NEXUS_HOME_ROOT", ".nexus"), home_dir)

      new(
        home_root: home_root,
        state_path: File.join(home_root, "state.sqlite3"),
        memory_root: File.join(home_root, "memory"),
        skills_root: File.join(home_root, "skills"),
        logs_root: File.join(home_root, "logs"),
        tmp_root: File.join(home_root, "tmp"),
        core_matrix_base_url: env["CORE_MATRIX_BASE_URL"],
        public_base_url: env.fetch("NEXUS_PUBLIC_BASE_URL", "http://#{http_bind}:#{http_port}"),
        http_bind: http_bind,
        http_port: http_port
      )
    end

    class << self
      private

      def expand_root(raw_root, home_dir)
        return File.join(home_dir, raw_root.delete_prefix("~/")) if raw_root.start_with?("~/")
        return raw_root if raw_root.start_with?("/")

        File.expand_path(raw_root, home_dir)
      end
    end
  end
end
