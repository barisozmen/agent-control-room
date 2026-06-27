# frozen_string_literal: true

require_relative "../railskit/base_generator"

# Makes this project a "native port hasher": its dev-server port is derived
# deterministically from the folder name (a hash into the band 3000..3999) so
# every tool — and every AI agent — can find the dev server without guessing or
# scanning. Ships bin/find_server_port (the resolver / single source of truth)
# and wires bin/dev to boot on it and record the chosen port.
#
# Safe to run on a mature Rails app that already has its own bin/dev: it injects
# the PORT-resolution lines ahead of the existing launcher rather than replacing
# it, and is idempotent (a second run skips).
class HashedPortsGenerator < Railskit::BaseGenerator
  FOREMAN_VERSION = "~> 0.90.0"

  desc "Deterministic per-project dev port: ships bin/find_server_port (hashes the " \
       "folder name into 3000..3999) and wires bin/dev to boot on it. Lets any tool " \
       "or agent resolve a project's dev port without guessing. Idempotent."

  # bin/ is not auto-copied by Railskit::BaseGenerator (only app/, config/, test/,
  # lib/, db/, public/, docs/), so we copy + chmod the resolver manually.
  def create_resolver_script
    template "bin/find_server_port.tt", "bin/find_server_port"
    chmod "bin/find_server_port", 0o755
  end

  def add_foreman_to_bundle
    @foreman_gem_added = false
    return unless file_exists?("Gemfile")
    return unless foreman_launcher?

    @foreman_gem_added = add_gem_unless_exists("foreman", FOREMAN_VERSION, group: :development)
  end

  # Boot bin/dev on the hashed port and record it, so bin/find_server_port can
  # report the exact live port (even under a collision) while the server runs.
  def wire_into_bin_dev
    return unless file_exists?("bin/dev")

    ensure_app_root_env
    ensure_port_resolution
    normalize_foreman_bootstrap if foreman_launcher?
  end

  def show_post_install_message
    next_steps = [
      "Run `bin/find_server_port` to see this project's port",
      "Start the server with `bin/dev` (override with PORT=xxxx bin/dev if needed)",
      "Copy this generator into other Rails apps to make them native port hashers too"
    ]
    next_steps.unshift("Run `bundle install` so Bundler can install Foreman") if @foreman_gem_added

    show_message "Deterministic dev port configured!",
      notes: [
        "bin/find_server_port hashes the folder name into 3000..3999 (single source of truth)",
        "bin/dev now boots on that port and records it to tmp/pids/dev_server.port",
        "Foreman launchers run through the app bundle with BUNDLE_GEMFILE pinned",
        "Resolve anywhere: `bin/find_server_port` or `bin/find_server_port --url`"
      ],
      next_steps: next_steps
  end

  private
    FOREMAN_INSTALL_BLOCK = /\n*if ! gem list foreman -i --silent; then\n[ \t]*echo "Installing foreman\.\.\."\n[ \t]*gem install foreman\nfi\n\n*/
    DEFAULT_PORT_BLOCK = Regexp.union(
      /^# Default to port 3000 if not specified\nexport PORT="\$\{PORT:-3000\}"\n\n?/,
      /^export PORT="\$\{PORT:-3000\}"\n\n?/
    )

    def ensure_app_root_env
      return if file_contains?("bin/dev", "APP_ROOT=")

      if bin_dev_content.match?(/^#!.*\n/)
        inject_into_file "bin/dev", app_root_block, after: /^#!.*\n/
      else
        prepend_to_file "bin/dev", app_root_block.lstrip
      end
    end

    def ensure_port_resolution
      gsub_file "bin/dev", DEFAULT_PORT_BLOCK, ""

      if file_contains?("bin/dev", "find_server_port")
        normalize_port_resolution_paths
        return
      end

      before = bin_dev_injection_point
      unless before
        say "bin/dev has no shell `exec` launcher to wire into (likely the Ruby " \
          "importmap form). Add this near the top yourself:\n" \
          "  export PORT=\"${PORT:-$(\"$APP_ROOT/bin/find_server_port\")}\"", :yellow
        return
      end

      inject_into_file "bin/dev", port_resolution_block, before: before
    end

    def normalize_foreman_bootstrap
      gsub_file "bin/dev", FOREMAN_INSTALL_BLOCK, "\n\n"
      return if bin_dev_content.match?(/^cd "\$APP_ROOT" \|\| exit 1\nexec bundle exec foreman\b/)

      gsub_file "bin/dev",
        /^exec (?:bundle exec )?foreman\b(.*)$/,
        "cd \"$APP_ROOT\" || exit 1\nexec bundle exec foreman\\1"
    end

    def normalize_port_resolution_paths
      gsub_file "bin/dev",
        'export PORT="${PORT:-$(bin/find_server_port)}"',
        'export PORT="${PORT:-$("$APP_ROOT/bin/find_server_port")}"'
      gsub_file "bin/dev",
        "mkdir -p tmp/pids && printf '%s' \"$PORT\" > tmp/pids/dev_server.port",
        "mkdir -p \"$APP_ROOT/tmp/pids\" && printf '%s' \"$PORT\" > \"$APP_ROOT/tmp/pids/dev_server.port\""
    end

    def foreman_launcher?
      file_exists?("bin/dev") && bin_dev_content.match?(/^exec (?:bundle exec )?foreman\b/)
    end

    def bin_dev_content
      File.read(File.expand_path("bin/dev", destination_root))
    end

    # First shell `exec` line in bin/dev — we insert the PORT export just above it,
    # so the chosen port is in the environment before the launcher (foreman/rails)
    # runs. Prefer the foreman launcher; fall back to any exec.
    def bin_dev_injection_point
      content = bin_dev_content
      return /^exec (?:bundle exec )?foreman\b.*$/ if content.match?(/^exec (?:bundle exec )?foreman\b/)
      return /^exec .*$/ if content.match?(/^exec /)

      nil
    end

    def app_root_block
      <<~SH

        APP_ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
        export BUNDLE_GEMFILE="$APP_ROOT/Gemfile"

      SH
    end

    def port_resolution_block
      <<~SH
        # Deterministic per-project dev port (hash of the folder name); see
        # bin/find_server_port. Override by setting PORT yourself.
        export PORT="${PORT:-$("$APP_ROOT/bin/find_server_port")}"

        # Record the chosen port so bin/find_server_port can report the live port
        # (exactly, even under a hash collision) while this server is running.
        mkdir -p "$APP_ROOT/tmp/pids" && printf '%s' "$PORT" > "$APP_ROOT/tmp/pids/dev_server.port"

      SH
    end
end
