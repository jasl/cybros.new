require "test_helper"
require "fileutils"
require "open3"
require_relative "../../../../lib/fenix/runtime/python_bootstrap"

class Fenix::Runtime::PythonBootstrapTest < ActiveSupport::TestCase
  test "default_versions_path falls back to installed nexus versions when repo-local matrix is unavailable" do
    Dir.mktmpdir("fenix-python-bootstrap-versions") do |tmpdir|
      missing = Pathname(tmpdir).join("missing.env")
      installed = Pathname(tmpdir).join("installed.env")
      File.write(installed, "PYTHON_MAJOR_MINOR=3.12\n")

      klass = Fenix::Runtime::PythonBootstrap.singleton_class
      original_method = klass.instance_method(:default_versions_candidates)
      klass.send(:define_method, :default_versions_candidates) { [missing, installed] }

      begin
        assert_equal installed, Fenix::Runtime::PythonBootstrap.send(:default_versions_path)
      ensure
        klass.send(:define_method, :default_versions_candidates, original_method)
      end
    end
  end

  test "ensure_ready provisions a managed python runtime under fenix home root and prepends it to PATH" do
    Dir.mktmpdir("fenix-python-bootstrap") do |tmpdir|
      fake_bin = File.join(tmpdir, "bin")
      home_root = File.join(tmpdir, "fenix-home")
      FileUtils.mkdir_p(fake_bin)

      stub_uv(fake_bin)

      env = {
        "PATH" => "#{fake_bin}:#{ENV.fetch("PATH")}",
        "FENIX_HOME_ROOT" => home_root,
      }

      root = Fenix::Runtime::PythonBootstrap.ensure_ready!(
        env: env,
        versions_path: Rails.root.join("../../images/nexus/versions.env")
      )

      assert_equal Pathname(home_root).join("python"), root
      assert_equal root.join("bin").to_s, env.fetch("PATH").split(File::PATH_SEPARATOR).first
      assert_equal root.to_s, env.fetch("FENIX_PYTHON_ROOT")
      assert_equal Pathname(home_root).join("toolchains", "python").to_s, env.fetch("UV_PYTHON_INSTALL_DIR")
      assert_equal "Python 3.12.0", Open3.capture2(env, root.join("bin", "python").to_s, "--version").first.strip
      assert_equal "Python 3.12.0", Open3.capture2(env, root.join("bin", "python3").to_s, "--version").first.strip
      assert_match(/\Apip /, Open3.capture2(env, root.join("bin", "pip").to_s, "--version").first.strip)
      assert_match(/\Apip /, Open3.capture2(env, root.join("bin", "pip3").to_s, "--version").first.strip)
    end
  end

  test "ensure_ready does not reprovision when the managed runtime already matches the requested version" do
    Dir.mktmpdir("fenix-python-bootstrap-existing") do |tmpdir|
      fake_bin = File.join(tmpdir, "bin")
      home_root = Pathname(tmpdir).join("fenix-home")
      runtime_root = home_root.join("python")
      FileUtils.mkdir_p(fake_bin)
      FileUtils.mkdir_p(runtime_root.join("bin"))
      write_python_stub(runtime_root.join("bin", "python"), "Python 3.12.9")
      write_python_stub(runtime_root.join("bin", "python3"), "Python 3.12.9")
      File.write(Pathname(tmpdir).join("uv.log"), "")
      stub_uv(fake_bin, log_path: Pathname(tmpdir).join("uv.log"))

      env = {
        "PATH" => "#{fake_bin}:#{ENV.fetch("PATH")}",
        "FENIX_HOME_ROOT" => home_root.to_s,
      }

      Fenix::Runtime::PythonBootstrap.ensure_ready!(
        env: env,
        versions_path: Rails.root.join("../../images/nexus/versions.env")
      )

      assert_equal "", Pathname(tmpdir).join("uv.log").read
      assert_equal runtime_root.join("bin").to_s, env.fetch("PATH").split(File::PATH_SEPARATOR).first
    end
  end

  private

  def stub_uv(bin_dir, log_path: nil)
    path = File.join(bin_dir, "uv")
    File.write(path, <<~SH)
      #!/bin/sh
      set -eu

      if [ "${1:-}" = "--version" ]; then
        echo "uv 0.11.5 (stub)"
        exit 0
      fi

      if [ "${1:-}" = "venv" ]; then
        #{log_path ? "echo \"$*\" >> #{log_path.to_s.inspect}" : ":"}

        target=""
        for arg in "$@"; do
          target="$arg"
        done

        mkdir -p "${target}/bin"
        cat > "${target}/bin/python" <<'PY'
#!/bin/sh
echo "Python 3.12.0"
PY
        cat > "${target}/bin/pip" <<'PIP'
#!/bin/sh
echo "pip 25.0 from ${0%/*}/../lib/python3.12/site-packages/pip (python 3.12)"
PIP
        cp "${target}/bin/python" "${target}/bin/python3"
        cp "${target}/bin/pip" "${target}/bin/pip3"
        chmod +x "${target}/bin/python" "${target}/bin/python3" "${target}/bin/pip" "${target}/bin/pip3"
        exit 0
      fi

      exit 1
    SH
    FileUtils.chmod("+x", path)
  end

  def write_python_stub(path, output)
    File.write(path, <<~SH)
      #!/bin/sh
      echo #{output.inspect}
    SH
    FileUtils.chmod("+x", path)
  end
end
