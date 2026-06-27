# frozen_string_literal: true

require "bundler"

module Railskit
  # Supported locales for all generators
  SUPPORTED_LOCALES = %w[en fr es de tr ru zh-CN uz].freeze

  # Thread-safe counter for unique migration timestamps
  @migration_timestamp_counter = nil
  @migration_timestamp_mutex = Mutex.new

  # Generates a unique migration timestamp by checking existing migrations.
  # Works across multiple generator processes by scanning db/migrate directory.
  def self.next_migration_timestamp
    @migration_timestamp_mutex.synchronize do
      current = Time.now.utc.strftime("%Y%m%d%H%M%S").to_i

      # Find highest existing migration timestamp
      migrate_dir = begin
        Rails.root.join("db/migrate")
      rescue StandardError
        "#{Dir.pwd}/db/migrate"
      end
      existing_max = Dir.glob("#{migrate_dir}/[0-9]*_*.rb")
                        .map { |f| File.basename(f)[/^\d+/].to_i }
                        .max || 0

      # Use the highest of: current time, existing max + 1, or last counter + 1
      @migration_timestamp_counter = [
        current,
        existing_max + 1,
        (@migration_timestamp_counter || 0) + 1
      ].max

      @migration_timestamp_counter.to_s
    end
  end

  # Tailwind color palette: color name -> hex value (500 shade)
  # Used for PWA manifest, favicon generation, and other contexts needing hex colors
  TAILWIND_COLORS = {
    "slate" => "#64748b", "gray" => "#6b7280", "zinc" => "#71717a",
    "neutral" => "#737373", "stone" => "#78716c", "red" => "#ef4444",
    "orange" => "#f97316", "amber" => "#f59e0b", "yellow" => "#eab308",
    "lime" => "#84cc16", "green" => "#22c55e", "emerald" => "#10b981",
    "teal" => "#14b8a6", "cyan" => "#06b6d4", "sky" => "#0ea5e9",
    "blue" => "#3b82f6", "indigo" => "#6366f1", "violet" => "#8b5cf6",
    "purple" => "#a855f7", "fuchsia" => "#d946ef", "pink" => "#ec4899",
    "rose" => "#f43f5e"
  }.freeze

  # Shared helper methods for all Railskit generators.
  #
  # These eliminate the most common patterns repeated across generators:
  # - Option parsing with ENV fallback and interactive prompts
  # - Safe file injection with guard patterns
  # - Prerequisite file checks
  # - Model method injection
  # - I18n translation injection
  # - Locale file copying
  #
  module GeneratorHelpers
    # Converts a Tailwind color name to its hex value.
    # Falls back to teal if color is not found.
    #
    # @param color_name [String] Tailwind color name (e.g., "teal", "blue", "indigo")
    # @return [String] Hex color value (e.g., "#14b8a6")
    #
    # @example
    #   tailwind_color_to_hex("teal")   # => "#14b8a6"
    #   tailwind_color_to_hex("blue")   # => "#3b82f6"
    #   tailwind_color_to_hex("unknown") # => "#14b8a6" (default teal)
    #
    def tailwind_color_to_hex(color_name)
      Railskit::TAILWIND_COLORS[color_name] || Railskit::TAILWIND_COLORS["teal"]
    end

    # Prompts with a default value. Returns default if user enters blank.
    def ask_with_default(question, default:)
      answer = ask("#{question} [#{default}]")
      answer.presence || default
    end

    def gem_exists?(name)
      gemfile_path = File.expand_path("Gemfile", destination_root)
      return false unless File.exist?(gemfile_path)

      File.read(gemfile_path).match?(/gem\s+["']#{name}["']/)
    end

    def add_gem_unless_exists(name, version, **options)
      if gem_exists?(name)
        say "  skip  #{name} already in Gemfile", :yellow
        return false
      end
      gem name, version, **options
      true
    end

    # Registers secrets for Kamal deployment by appending to a manifest file.
    # Other generators call this to declare their secrets, and kamal_deploy reads it.
    #
    # @param secrets [Array<String>] Secrets in "APP_NAME" or "APP_NAME:VAULT_NAME" format
    #
    # @example
    #   register_kamal_secrets "GOOGLE_CLIENT_ID", "GOOGLE_CLIENT_SECRET"
    #   register_kamal_secrets "RESEND_API_KEY"
    #
    def register_kamal_secrets(*secrets)
      manifest = File.join(destination_root, ".kamal_secrets_manifest")
      File.open(manifest, "a") { |f| secrets.each { |s| f.puts s } }
    end

    # Registers a recurring job in `config/recurring.yml` (Solid Queue).
    # Idempotent — running twice does not duplicate the entry.
    # Creates the file with a `production:` key if missing.
    #
    # Pass exactly one of `command:` (a Ruby expression string) or `class:`
    # (a job class name). `schedule:` uses Solid Queue cron-like syntax.
    #
    # @param name [Symbol, String] Job entry key (e.g. :purge_soft_deleted)
    # @param command [String, nil] Ruby command to run (e.g. "MagicLink.cleanup")
    # @param class [String, nil] Job class name (e.g. "PurgeSoftDeletedJob")
    # @param schedule [String] Schedule expression (e.g. "every day at 04:30")
    # @return [Boolean] true if added, false if already present
    #
    # @example Command-style entry
    #   register_recurring_job(:cleanup_magic_links,
    #     command: "MagicLink.cleanup",
    #     schedule: "every day at 04:00")
    #
    # @example Class-style entry
    #   register_recurring_job(:purge_soft_deleted,
    #     class: "PurgeSoftDeletedJob",
    #     schedule: "every day at 04:30")
    #
    def register_recurring_job(name, schedule:, command: nil, **opts)
      job_class = opts[:class]
      if (command.nil? && job_class.nil?) || (command && job_class)
        raise ArgumentError, "register_recurring_job requires exactly one of `command:` or `class:`"
      end

      path = "config/recurring.yml"
      full_path = File.expand_path(path, destination_root)

      unless File.exist?(full_path)
        create_file path, "production:\n"
      end

      key = name.to_s
      if file_contains?(path, /^\s+#{Regexp.escape(key)}:\s*$/)
        say "  skip  recurring job #{key.inspect} already registered", :yellow
        return false
      end

      body = command ? %(    command: "#{command}") : %(    class: "#{job_class}")
      fragment = <<~YAML
        \n  #{key}:
        #{body}
            schedule: #{schedule}
      YAML

      inject_into_file path, fragment, after: /^production:.*\n/
      say "Registered recurring job #{key.inspect} in #{path}", :green
      true
    end

    # Runs bundle install in a clean Bundler environment.
    # Use this after adding gems to ensure they're installed.
    #
    # Set SKIP_BUNDLE_INSTALL_IN_GENERATORS=1 to skip (for batch installs).
    #
    # @param quiet [Boolean] Suppress bundle output (default: true)
    # @param immediate [Boolean] Force install even when SKIP_BUNDLE_INSTALL_IN_GENERATORS=1 (default: false)
    #
    # @example
    #   add_gem_unless_exists "my_gem", "~> 1.0"
    #   bundle_install
    #
    # @example Force immediate install (e.g., when gem is needed by subsequent generators)
    #   add_gem_unless_exists "cuprite", "~> 0.17", group: :test
    #   bundle_install(immediate: true)
    #
    def bundle_install(quiet: true, immediate: false)
      return if !immediate && ENV["SKIP_BUNDLE_INSTALL_IN_GENERATORS"] == "1"

      Bundler.with_unbundled_env do
        # Limit parallelism to avoid CPU overload during generation
        max_jobs = "4"
        ENV["BUNDLE_JOBS"] = max_jobs
        ENV["MAKEFLAGS"] = "-j#{max_jobs}"

        run "bundle install#{" --quiet" if quiet}"
      end
    end

    # Resolves option value with fallback chain: CLI option -> ENV var -> prompt.
    #
    # @param name [Symbol] Option name (also used for instance variable)
    # @param env [String, nil] Environment variable name to check (optional)
    # @param prompt [String, nil] Interactive prompt if no value found (optional)
    # @param default [Object, Proc] Default value if nothing provided. Can be a Proc for lazy evaluation.
    # @return [Object] The resolved value
    #
    # @example
    #   # In generator:
    #   @app_name = option_with_fallback(:app_name, env: "APP_NAME", prompt: "App name?", default: "MyApp")
    #
    #   # With lazy default (avoids calling Rails.application in tests):
    #   @app_name = option_with_fallback(:app_name, env: "APP_NAME", prompt: "App name?",
    #     default: -> { Rails.application.class.module_parent_name.titleize })
    #
    def option_with_fallback(name, env: nil, prompt: nil, default: nil)
      # Check CLI option first
      value = options[name].presence
      return value if value

      # Check ENV variable
      value = ENV[env].presence if env
      return value if value

      # Resolve default only when needed (supports Proc for lazy evaluation)
      resolved_default = default.respond_to?(:call) ? default.call : default

      # Interactive prompt
      if prompt
        value = ask_with_default(prompt, default: resolved_default)
        return value if value.present?
      end

      # Fall back to default
      resolved_default
    end

    # Safely injects content into a file only if the guard pattern is not present.
    #
    # @param path [String] File path to modify
    # @param guard [String, Regexp] Pattern to check - skips if already present
    # @param content [String] Content to inject
    # @param opts [Hash] Options passed to inject_into_file (:before, :after, etc.)
    # @return [Boolean] true if injected, false if skipped
    #
    # @example
    #   safe_inject("config/routes.rb",
    #     guard: "resource :registration",
    #     content: "resource :registration, only: [:new, :create]\n",
    #     after: /resource :session/)
    #
    def safe_inject(path, guard:, content:, **opts)
      # Resolve full path relative to destination_root (for generator context)
      full_path = File.expand_path(path, destination_root)

      unless File.exist?(full_path)
        say "File not found: #{path}", :yellow
        return false
      end

      file_content = File.read(full_path)

      if file_content.match?(normalize_guard(guard))
        say "  skip  #{guard.inspect} already exists in #{path}", :yellow
        return false
      end

      inject_into_file(path, content, **opts)
      true
    end

    # Raises an error if a required file doesn't exist.
    #
    # @param path [String] Path to check
    # @param message [String] Error message explaining the prerequisite
    # @raise [Thor::Error] if file doesn't exist
    #
    # @example
    #   require_file!("app/controllers/sessions_controller.rb",
    #     "Run 'bin/rails generate authentication' first")
    #
    def require_file!(path, message)
      full_path = File.expand_path(path, destination_root)
      return true if File.exist?(full_path)

      say_status :error, "#{path} not found. #{message}", :red
      raise Thor::Error, message
    end

    # Checks if a route pattern exists in config/routes.rb.
    # Convenience wrapper around file_contains? for the common route-checking pattern.
    #
    # @param pattern [String, Regexp] Route pattern to search for
    # @return [Boolean] true if routes.rb contains the pattern
    #
    # @example
    #   if route_exists?("resource :session")
    #     say "Session route already exists", :yellow
    #   end
    #
    #   unless route_exists?(/get\s+["']\/profile["']/)
    #     # Add profile route
    #   end
    #
    def route_exists?(pattern)
      file_contains?("config/routes.rb", pattern)
    end

    # Validates that required model files exist.
    # Raises an error if any model is missing, providing clear guidance.
    #
    # @param model_names [Array<String>] Model names to check (e.g., "User", "Session")
    # @raise [Thor::Error] if any model file doesn't exist
    #
    # @example
    #   require_models!("User", "Session")
    #   # Raises error: "User model not found at app/models/user.rb. Run migrations first."
    #
    def require_models!(*model_names)
      model_names.flatten.each do |model|
        require_file!(
          "app/models/#{model.underscore}.rb",
          "#{model} model not found. Run 'bin/rails generate model #{model}' first."
        )
      end
    end

    # Checks if a file exists, with optional warning on missing files.
    # Useful for guard clauses that skip optional operations.
    #
    # @param path [String] File path to check
    # @param warn [Boolean] Whether to display a warning if file not found (default: true)
    # @return [Boolean] true if file exists
    #
    # @example Skip with warning (default)
    #   return unless file_exists?("app/views/layouts/_navbar.html.erb")
    #
    # @example Silent check
    #   return unless file_exists?(path, warn: false)
    #
    def file_exists?(path, warn: true)
      full_path = File.expand_path(path, destination_root)
      return true if File.exist?(full_path)

      say "Warning: #{path} not found. Skipping.", :yellow if warn
      false
    end

    # Checks if a file exists and contains a pattern.
    # Reduces Feature Envy by centralizing File.read/File.exist? operations.
    #
    # @param path [String] File path to check
    # @param pattern [String, Regexp] Pattern to search for
    # @return [Boolean] true if file exists and contains pattern
    #
    # @example
    #   if file_contains?("config/routes.rb", "resource :session")
    #     # Route already exists
    #   end
    #
    #   if file_contains?("app/controllers/sessions_controller.rb", /def show/)
    #     # Method already defined
    #   end
    #
    def file_contains?(path, pattern)
      full_path = File.expand_path(path, destination_root)
      return false unless File.exist?(full_path)

      content = File.read(full_path)
      pattern.is_a?(Regexp) ? content.match?(pattern) : content.include?(pattern)
    end

    # Injects code into a model class if the guard pattern is not present.
    #
    # @param model [String] Model name (e.g., "User")
    # @param guard [String, Regexp] Pattern to check - skips if present
    # @param code [String] Ruby code to inject into the class
    # @return [Boolean] true if injected, false if skipped or file missing
    #
    # @example
    #   add_to_model("User", guard: "has_many :posts", code: <<~RUBY)
    #     has_many :posts, dependent: :destroy
    #   RUBY
    #
    def add_to_model(model, guard:, code:, section: :public)
      inject_into_class_safely(
        path: "app/models/#{model.underscore}.rb",
        class_name: model,
        label: "#{model} model",
        guard: guard,
        code: code,
        section: section
      )
    end

    # Injects code into a controller class if the guard pattern is not present.
    #
    # @param controller [String] Controller name without "Controller" suffix (e.g., "Sessions", "Application")
    # @param guard [String, Regexp] Pattern to check - skips if present
    # @param code [String] Ruby code to inject into the class
    # @return [Boolean] true if injected, false if skipped or file missing
    #
    # @example
    #   add_to_controller("Sessions", guard: "def show", code: <<~RUBY)
    #     def show
    #       redirect_to root_path
    #     end
    #   RUBY
    #
    # @example With namespaced controller
    #   add_to_controller("Admin::Dashboard", guard: "before_action :require_admin", code: <<~RUBY)
    #     before_action :require_admin
    #   RUBY
    #
    def add_to_controller(controller, guard:, code:, section: :public)
      inject_into_class_safely(
        path: "app/controllers/#{controller.underscore}_controller.rb",
        class_name: "#{controller}Controller",
        label: "#{controller}Controller",
        guard: guard,
        code: code,
        section: section
      )
    end

    def include_in_model(model, concern)
      add_to_model(model,
        guard: /^\s*include\s+#{Regexp.escape(concern)}\b/,
        code: "  include #{concern}\n")
    end

    def include_in_controller(controller, concern)
      add_to_controller(controller,
        guard: /^\s*include\s+#{Regexp.escape(concern)}\b/,
        code: "  include #{concern}\n")
    end

    # Shared implementation for add_to_model / add_to_controller.
    # Reads the file, checks the guard, and injects into the named class.
    #
    # @param path [String] Relative file path (e.g., "app/models/user.rb")
    # @param class_name [String] Class to inject into (passed to inject_into_class)
    # @param label [String] Human-readable label for messages
    # @param guard [String, Regexp] Pattern to check - skips if present
    # @param code [String] Ruby code to inject into the class
    # @return [Boolean] true if injected, false if skipped or file missing
    #
    def inject_into_class_safely(path:, class_name:, label:, guard:, code:, section: :public)
      full_path = File.expand_path(path, destination_root)

      unless File.exist?(full_path)
        say "#{label} not found at #{path}. Add manually.", :red
        return false
      end

      if File.read(full_path).match?(normalize_guard(guard))
        say "  skip  #{guard.inspect} already exists in #{label}", :yellow
        return false
      end

      return false unless inject_into_class_section(path, class_name, code, section: section)

      say "Added #{guard.inspect} to #{label}", :green
      true
    end

    def inject_into_class_section(path, class_name, code, section:)
      if section == :after_class
        inject_into_class(path, class_name, code)
        return true
      end

      full_path = File.expand_path(path, destination_root)
      content = File.read(full_path)
      bounds = class_body_bounds(content, class_name)

      unless bounds
        say "Class #{class_name} not found in #{path}. Add manually.", :red
        return false
      end

      updated = case section
      when :public
        inject_public_class_code(content, bounds, code)
      when :private
        inject_private_class_code(content, bounds, code)
      else
        raise ArgumentError, "Unknown class injection section: #{section.inspect}"
      end

      File.write(full_path, updated)
      true
    end

    def class_body_bounds(content, class_name)
      lines = content.lines
      class_pattern = /^\s*class\s+#{Regexp.escape(class_name)}(?:\s|<|$)/
      start_index = lines.index { |line| line.match?(class_pattern) }
      return unless start_index

      depth = 0
      lines.each_with_index.drop(start_index).each do |line, index|
        depth += ruby_block_open_delta(line)
        depth -= 1 if ruby_end_line?(line)
        return { lines: lines, body_start: start_index + 1, body_end: index } if index > start_index && depth.zero?
      end

      nil
    end

    def inject_public_class_code(_content, bounds, code)
      lines = bounds[:lines]
      visibility_index = top_level_visibility_index(lines, bounds)
      insert_at = visibility_index || bounds[:body_end]
      insert_lines(lines, insert_at, normalize_class_code(code))
    end

    def inject_private_class_code(_content, bounds, code)
      lines = bounds[:lines]
      private_index = top_level_visibility_index(lines, bounds, visibility: "private")

      if private_index
        insert_lines(lines, private_index + 1, normalize_class_code(code))
      else
        private_block = "\n  private\n#{normalize_class_code(code)}"
        insert_lines(lines, bounds[:body_end], private_block)
      end
    end

    def top_level_visibility_index(lines, bounds, visibility: nil)
      depth = 1
      visibilities = visibility ? [ visibility ] : %w[private protected]

      (bounds[:body_start]...bounds[:body_end]).each do |index|
        line = lines[index]
        return index if depth == 1 && line.match?(/^\s*(#{visibilities.join("|")})\s*$/)

        depth += ruby_block_open_delta(line)
        depth -= 1 if ruby_end_line?(line)
      end

      nil
    end

    def normalize_class_code(code)
      normalized = code.end_with?("\n") ? code : "#{code}\n"
      return normalized unless normalized.lines.any? { |line| line.match?(/\A\S/) }

      normalized.lines.map { |line| line.strip.empty? ? line : "  #{line}" }.join
    end

    def insert_lines(lines, index, code)
      result = lines.dup
      result.insert(index, code)
      result.join
    end

    def ruby_block_open_delta(line)
      stripped = line.sub(/#.*/, "").strip
      return 0 if stripped.empty?
      return 0 if stripped.match?(/\A(end|else|elsif|when|rescue|ensure)\b/)

      delta = 0
      delta += 1 if stripped.match?(/\A(class|module|if|unless|case|begin|for|while|until)\b/)
      delta += 1 if stripped.match?(/\Adef\b/) && !stripped.match?(/\Adef\b.*=/)
      delta += 1 if stripped.match?(/\bdo(\s*\|[^|]*\|)?\s*\z/)
      delta
    end

    def ruby_end_line?(line)
      line.sub(/#.*/, "").strip == "end"
    end

    # Adds translations to a locale file under a specific key.
    #
    # @param locale [String] Locale code (e.g., "en")
    # @param guard [String] Key to check - skips if present (e.g., "sign_up:")
    # @param content [String] YAML content to inject (already indented)
    # @param parent_key [String, nil] Parent key to inject under (e.g., "auth:")
    # @param namespace [String, nil] Subdirectory for locale file (e.g., "navbar" for config/locales/navbar/en.yml)
    # @return [Boolean] true if added, false if skipped or file missing
    #
    # @example Basic usage
    #   add_translations("en", guard: "sign_up:", content: <<~YAML, parent_key: "auth:")
    #       sign_up: "Sign Up"
    #       sign_up_subtitle: "Create your account"
    #   YAML
    #
    # @example With namespace for subdirectory
    #   add_translations("en", guard: "billing:", content: 'billing: "Billing"',
    #                    parent_key: "navbar:", namespace: "navbar")
    #
    def add_translations(locale, guard:, content:, parent_key: nil, namespace: nil)
      locale_file = namespace ? "config/locales/#{namespace}/#{locale}.yml" : "config/locales/#{locale}.yml"
      full_path = File.expand_path(locale_file, destination_root)

      unless File.exist?(full_path)
        say "Locale file not found: #{locale_file}", :yellow
        return false
      end

      locale_content = File.read(full_path)

      if locale_content.match?(normalize_guard(guard))
        say "  skip  #{guard.inspect} translations already exist", :yellow
        return false
      end

      if parent_key && locale_content.include?(parent_key)
        # Add proper indentation (2 spaces) to each line when nesting under parent_key
        indented_content = content.lines.map { |line| line.empty? || line.strip.empty? ? line : "  #{line}" }.join
        inject_into_file(locale_file, indented_content, after: /#{Regexp.escape(parent_key)}\s*\n/)
      else
        # Append to end of file
        inject_into_file(locale_file, "\n#{content}", before: /\z/)
      end

      say "Added #{guard.inspect} translations to #{locale_file}", :green
      true
    end

    # Displays a standardized post-install message with consistent formatting.
    #
    # @param title [String] The success message title
    # @param files [Array<String>] List of files created (alias: files_created)
    # @param files_modified [Array<String>] List of files modified
    # @param configuration [Array<String>] Configuration items added
    # @param notes [Array<String>] Additional notes or usage tips
    # @param next_steps [Array<String>] Numbered action items for the user
    # @param commands [Hash<String, String>] Useful commands (name => description)
    #
    # @example Basic usage
    #   show_message "Tailwind UI Helpers configured!",
    #     files: %w[app/helpers/ui_helper.rb app/helpers/ui/buttons.rb],
    #     notes: ["Include UiHelper in ApplicationHelper"],
    #     next_steps: ["Run bundle install", "Restart your server"]
    #
    # @example Full usage with all sections
    #   show_message "Kamal Deployment Setup Complete!",
    #     files_modified: ["config/deploy.yml", ".kamal/secrets"],
    #     files: ["bin/deploy", "lib/tasks/live_healthcheck.rake"],
    #     next_steps: ["Edit config/deploy.yml with your server IP", "Run: kamal setup"],
    #     commands: { "kamal console" => "Rails console", "kamal logs" => "Follow logs" }
    #
    def show_message(title, files: [], files_modified: [], configuration: [], notes: [], next_steps: [], commands: {})
      say ""
      say "=" * 60, :green
      say " #{title}", :green
      say "=" * 60, :green
      say ""

      if files_modified.any?
        say "Files modified:", :yellow
        files_modified.each { |f| say "  - #{f}" }
        say ""
      end

      if files.any?
        say "Files created:", :cyan
        files.each { |f| say "  - #{f}" }
        say ""
      end

      if configuration.any?
        say "Configuration added:", :cyan
        configuration.each { |c| say "  - #{c}" }
        say ""
      end

      if notes.any?
        say "Notes:", :yellow
        notes.each { |n| say "  #{n}" }
        say ""
      end

      if next_steps.any?
        say "Next steps:", :yellow
        next_steps.each_with_index { |s, i| say "  #{i + 1}. #{s}" }
        say ""
      end

      return unless commands.any?

      say "Useful commands:", :cyan
      commands.each { |cmd, desc| say "  #{cmd.ljust(16)} - #{desc}" }
      say ""
    end

    # Copies locale files for a generator namespace.
    #
    # Expects locale templates at templates/locales/#{namespace}/#{locale}.yml.tt
    # and copies to config/locales/#{namespace}/#{locale}.yml
    #
    # Requires: class_option :locales, type: :string, default: "en"
    #
    # @param namespace [String] The locale namespace (e.g., "footer", "admin", "profile")
    #
    # @example
    #   # In generator:
    #   class_option :locales, type: :string, default: "en"
    #
    #   def copy_locale_files
    #     copy_locales_for("footer")
    #   end
    #
    def copy_locales_for(namespace)
      locales = options[:locales].split(",").map(&:strip)
      locales.each do |locale|
        next unless Railskit::SUPPORTED_LOCALES.include?(locale)

        template "locales/#{namespace}/#{locale}.yml.tt",
                 "config/locales/#{namespace}/#{locale}.yml"
      end
    end

    # Adds a test method to the live_healthcheck.rake file.
    # Used by generators that need production health verification (resend, sentry, etc.)
    #
    # @param method_name [String] The name of the test method (e.g., "test_email_can_be_sent")
    # @param method_code [String] The Ruby code for the test method (including def...end)
    # @param description [String] Human-readable description for log messages (default: method_name)
    # @return [Boolean] true if added, false if skipped or file missing
    #
    # @example
    #   add_healthcheck_test(
    #     method_name: "test_email_can_be_sent",
    #     method_code: <<~'METHOD',
    #       def test_email_can_be_sent(to_email)
    #         # test logic here
    #       end
    #     METHOD
    #     description: "Email delivery test"
    #   )
    #
    def add_healthcheck_test(method_name:, method_code:, description: nil)
      healthcheck_file = "lib/tasks/live_healthcheck.rake"
      description ||= method_name

      return false unless file_exists?(healthcheck_file)

      if file_contains?(healthcheck_file, method_name)
        say "#{description} already exists in live_healthcheck.rake", :yellow
        return false
      end

      # Ensure method_code starts with newline for clean formatting
      formatted_code = method_code.start_with?("\n") ? method_code : "\n#{method_code}"

      inject_into_file healthcheck_file,
                       formatted_code,
                       before: /^end\s*$/

      say "Added #{description} to live_healthcheck.rake", :green
      true
    end

    # Injects routes into config/routes.rb with guard pattern.
    # Common pattern for generators that add routes.
    #
    # @param content [String] Route content to inject (will be indented 2 spaces)
    # @param guard [String, Regexp, nil] Guard pattern (defaults to first line of content)
    # @return [Boolean] true if injected, false if skipped
    #
    # @example
    #   inject_routes("resources :posts")
    #   inject_routes("get 'pricing', to: 'pricing#index'", guard: "pricing")
    #
    def inject_routes(content, guard: nil)
      guard ||= content.lines.first.strip
      # Always end with a newline. Multiple generators inject at the same
      # anchor ("Rails.application.routes.draw do\n"); without a trailing
      # newline, two routes get glued together on one line (syntax error).
      content = "#{content}\n" unless content.end_with?("\n")
      first_route_line = content.lines.find { |line| !line.strip.empty? }&.strip

      if first_route_line&.start_with?("resolve ")
        safe_inject("config/routes.rb",
          guard: guard,
          content: content.indent(2),
          after: "Rails.application.routes.draw do\n")
      elsif file_contains?("config/routes.rb", 'scope "(:locale)"')
        safe_inject("config/routes.rb",
          guard: guard,
          content: content.indent(4),
          after: /^  scope "\(:locale\)".*do\n/)
      else
        safe_inject("config/routes.rb",
          guard: guard,
          content: content.indent(2),
          after: "Rails.application.routes.draw do\n")
      end
    end

    # Injects links into navbar (desktop and mobile sections).
    # Common pattern for generators that add navbar navigation.
    #
    # @param desktop_erb [String] ERB for desktop navbar link
    # @param mobile_erb [String] ERB for mobile drawer link
    # @param guard [String] Guard pattern to prevent duplicates
    # @param desktop_after [String, Regexp] Position marker for desktop link
    # @param mobile_after [String, Regexp, nil] Position marker for mobile link (after)
    # @param mobile_before [String, Regexp, nil] Position marker for mobile link (before)
    # @return [Boolean] true if injected, false if navbar missing
    #
    # @example Menu dropdown injection
    #   inject_navbar_link(
    #     "<%%= menu_item 'Profile', profile_path %>",
    #     "<%%= link_to 'Profile', profile_path, class: '...' %>",
    #     guard: "profile_path",
    #     desktop_after: "<%%= menu_item t('navbar.settings') %>",
    #     mobile_before: "<%%= link_to t('navbar.logout') %>"
    #   )
    #
    def inject_navbar_link(desktop_erb, mobile_erb, guard:, desktop_after:, mobile_before: nil, mobile_after: nil)
      navbar_path = "app/views/layouts/_navbar.html.erb"
      return false unless file_exists?(navbar_path)

      # Desktop link
      safe_inject(navbar_path,
        guard: guard,
        content: "\n          #{desktop_erb}",
        after: desktop_after)

      # Mobile link
      mobile_opts = if mobile_before
        { before: mobile_before }
      else
        { after: mobile_after }
      end

      safe_inject(navbar_path,
        guard: "mobile.*#{guard}",
        content: mobile_before ? "#{mobile_erb}\n        " : "#{mobile_erb}\n      ",
        **mobile_opts)
    end

    # Includes a helper module in ApplicationHelper.
    # Common pattern for generators that create view helpers.
    #
    # @param helper_name [String] The helper module name (e.g., "AvatarHelper", "MarkdownHelper")
    # @return [Boolean] true if included, false if already present or file missing
    #
    # @example
    #   include_helper_in_application("AvatarHelper")
    #   # Injects: include AvatarHelper
    #
    def include_helper_in_application(helper_name)
      helper_file = "app/helpers/application_helper.rb"

      return false unless file_exists?(helper_file)

      if file_contains?(helper_file, "include #{helper_name}")
        say "  skip  #{helper_name} already included in ApplicationHelper", :yellow
        return false
      end

      inject_into_file helper_file,
                       "  include #{helper_name}\n",
                       after: "module ApplicationHelper\n"

      say "Added #{helper_name} to ApplicationHelper", :green
      true
    end

    # Validates that show_post_install_message uses show_message helper.
    # Detects manual formatting patterns that should use the standardized helper.
    #
    # @return [Boolean] true if validation passes, false if manual formatting detected
    #
    def validate_post_install_message_format
      return true unless respond_to?(:show_post_install_message)

      begin
        # method_source gem provides .source method on Method objects
        # Skip validation if gem is not available
        method_source = method(:show_post_install_message).source
      rescue NoMethodError, NameError
        # method_source gem not installed or method can't be parsed
        return true
      end

      # Detect manual formatting patterns
      manual_patterns = [
        /say\s+["']={30,}/, # say "=" * 70 separators
        /say\s+["']\*{30,}/,           # say "*" * 70 separators
        /say\s+["']-,{30,}/,           # say "-" * 70 separators
        /say\s+:[a-z]+,\s*:[a-z]+/, # say :green, :cyan color patterns
        /say\s+["']\s*[A-Z][^"']*["']\s*$/ # say "ALL CAPS HEADERS"
      ]

      if manual_patterns.any? { |pattern| method_source.match?(pattern) }
        say ""
        say "⚠️  Warning: #{self.class.name} uses manual message formatting.", :yellow
        say "   Use show_message helper for consistent output:", :yellow
        say '   show_message "Title",', :yellow
        say "     files: [...],", :yellow
        say "     notes: [...],", :yellow
        say "     next_steps: [...]", :yellow
        say ""
        return false
      end

      true
    end

    private

    # Normalizes a guard pattern to a Regexp for consistent matching.
    # Accepts either a String (which gets escaped) or a Regexp (used as-is).
    def normalize_guard(guard)
      guard.is_a?(Regexp) ? guard : Regexp.new(Regexp.escape(guard))
    end
  end
end
