require "fileutils"
require "open3"
require "pathname"

module Nexus
  module Runtime
    class PythonBootstrap
      BootstrapError = Class.new(StandardError)

      class << self
        def ensure_ready!(env: ENV, versions_path: default_versions_path)
          versions = load_versions(versions_path)
          home_root = resolve_home_root(env)
          runtime_root = resolve_runtime_root(env, home_root)
          install_root = resolve_install_root(env, home_root)

          FileUtils.mkdir_p(home_root)
          with_bootstrap_lock(home_root) do
            provision_runtime!(
              env: env,
              runtime_root: runtime_root,
              install_root: install_root,
              python_request: versions.fetch("PYTHON_MAJOR_MINOR")
            ) unless python_ready?(runtime_root, versions.fetch("PYTHON_MAJOR_MINOR"))
          end

          apply_environment!(env, home_root: home_root, runtime_root: runtime_root, install_root: install_root)
          runtime_root
        end

        private

        def default_versions_path
          default_versions_candidates.find(&:exist?) || default_versions_candidates.first
        end

        def default_versions_candidates
          [
            Pathname.new(__dir__).join("../../../../../images/nexus/versions.env").expand_path,
            Pathname.new("/usr/local/share/nexus/versions.env"),
          ]
        end

        def load_versions(path)
          Pathname.new(path).read.each_line.each_with_object({}) do |line, versions|
            next if line.strip.empty? || line.start_with?("#")

            key, value = line.strip.split("=", 2)
            versions[key] = value if key && value
          end
        end

        def resolve_home_root(env)
          raw_home_root = env["NEXUS_HOME_ROOT"]
          raw_home_root = raw_home_root.to_s.strip
          return Pathname.new(raw_home_root).expand_path unless raw_home_root.empty?

          Pathname.new(Dir.home).join(".nexus")
        end

        def resolve_runtime_root(env, home_root)
          raw_root = env["NEXUS_PYTHON_ROOT"].to_s.strip
          return Pathname.new(raw_root).expand_path unless raw_root.empty?

          home_root.join("python")
        end

        def resolve_install_root(env, home_root)
          raw_root = env["NEXUS_PYTHON_INSTALL_ROOT"].to_s.strip
          return Pathname.new(raw_root).expand_path unless raw_root.empty?

          home_root.join("toolchains", "python")
        end

        def python_ready?(runtime_root, python_request)
          python_bin = runtime_root.join("bin", "python")
          python3_bin = runtime_root.join("bin", "python3")
          return false unless python_bin.exist? && python3_bin.exist?

          [python_bin, python3_bin].all? do |command|
            stdout, status = Open3.capture2e(command.to_s, "--version")
            status.success? && stdout.start_with?("Python #{python_request}")
          end
        end

        def provision_runtime!(env:, runtime_root:, install_root:, python_request:)
          FileUtils.rm_rf(runtime_root)
          FileUtils.mkdir_p(install_root)

          command_env = env.to_h.merge("UV_PYTHON_INSTALL_DIR" => install_root.to_s)
          stdout, status = Open3.capture2e(
            command_env,
            "uv",
            "venv",
            "--python",
            python_request,
            "--seed",
            runtime_root.to_s
          )
          return if status.success?

          raise BootstrapError, "uv failed to provision Python #{python_request} at #{runtime_root}: #{stdout}"
        end

        def apply_environment!(env, home_root:, runtime_root:, install_root:)
          runtime_bin = runtime_root.join("bin").to_s
          path_entries = env.fetch("PATH", "").split(File::PATH_SEPARATOR).reject(&:empty?)
          path_entries.delete(runtime_bin)

          env["NEXUS_HOME_ROOT"] = home_root.to_s
          env["NEXUS_PYTHON_ROOT"] = runtime_root.to_s
          env["NEXUS_PYTHON_INSTALL_ROOT"] = install_root.to_s
          env["UV_PYTHON_INSTALL_DIR"] = install_root.to_s
          env["PATH"] = ([runtime_bin] + path_entries).join(File::PATH_SEPARATOR)
        end

        def with_bootstrap_lock(home_root)
          lock_path = home_root.join(".python-bootstrap.lock")
          File.open(lock_path, File::RDWR | File::CREAT, 0o644) do |lock|
            lock.flock(File::LOCK_EX)
            yield
          end
        end
      end
    end
  end
end
