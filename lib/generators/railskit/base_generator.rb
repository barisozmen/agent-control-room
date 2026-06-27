# frozen_string_literal: true

require_relative "generator_helpers"

module Railskit
  # Base generator providing shared functionality for all Railskit generators.
  #
  # Usage:
  #   class MyGenerator < Railskit::BaseGenerator
  #     # templates are automatically loaded from lib/generators/my/templates
  #   end
  #
  # Auto-Copy Convention:
  #   Templates in app/, config/, test/, lib/, db/, public/, docs/ are automatically
  #   copied with paths mirroring their destination:
  #     templates/app/helpers/foo.rb.tt  →  app/helpers/foo.rb
  #
  # Exclusions:
  #   class MyGenerator < Railskit::BaseGenerator
  #     exclude_templates "app/views/authors/**/*"  # Class-level exclusion
  #
  #     def set_options
  #       exclude_template "app/views/authors/**/*" if options[:skip_authors]  # Runtime
  #     end
  #   end
  #
  # Locales:
  #   class MyGenerator < Railskit::BaseGenerator
  #     with_locales "my_namespace"  # Auto-adds :locales option and copy_locale_files method
  #   end
  #
  class BaseGenerator < Rails::Generators::Base
    include Rails::Generators::Migration
    include GeneratorHelpers

    class_attribute :template_exclusions, default: []
    class_attribute :locale_namespace, default: nil
    class_attribute :declared_env_options, default: []

    # DSL: exclude_templates "pattern", "another/pattern/**/*"
    # Patterns use File.fnmatch? with FNM_PATHNAME flag
    def self.exclude_templates(*patterns)
      self.template_exclusions = template_exclusions + patterns.flatten
    end

    # DSL: declare a CLI option with ENV fallback, optional interactive prompt, and default.
    #
    # Replaces the per-generator boilerplate:
    #
    #   class_option :app_name, type: :string, desc: "..."
    #   def set_options
    #     @app_name = option_with_fallback(:app_name, env: "APP_NAME",
    #       prompt: "App name?", default: "MyApp")
    #   end
    #
    # With a single declarative line:
    #
    #   option_with_env :app_name, env: "APP_NAME",
    #     prompt: "App name?", default: "MyApp", desc: "..."
    #
    # The matching @<name> instance variable is auto-populated at the start of
    # invoke_all (before any step methods run), so ERB templates and step methods
    # can use it directly. Pass a block to post-process the resolved value:
    #
    #   option_with_env :features, env: "APP_FEATURES",
    #     prompt: "Features (comma-separated):", default: "Fast,Secure,Simple" do |v|
    #     v.split(",").map(&:strip)
    #   end
    def self.option_with_env(name, env:, prompt: nil, default: nil, desc: nil, &transform)
      class_option name, type: :string, default: nil, desc: desc || prompt
      self.declared_env_options = declared_env_options + [
        { name: name, env: env, prompt: prompt, default: default, transform: transform }
      ]
    end

    # Required by Rails::Generators::Migration - provides timestamped migration numbers
    def self.next_migration_number(dirname)
      next_migration_number = current_migration_number(dirname) + 1
      ActiveRecord::Migration.next_migration_number(next_migration_number)
    end

    def self.inherited(subclass)
      super
      # Auto-set source_root to templates/ relative to subclass file location
      # Capture path before entering class_eval where caller context changes
      subclass_path = caller_locations(1, 1).first.path
      subclass.class_eval do
        source_root File.expand_path("templates", File.dirname(subclass_path))
      end
    end

    # Declares locale support for this generator.
    # Adds :locales class_option and defines copy_locale_files method.
    #
    # @param namespace [String] The locale namespace (e.g., "billing", "profile")
    #
    # @example
    #   class StripeBillingGenerator < Railskit::BaseGenerator
    #     with_locales "billing"
    #     # Adds: class_option :locales, type: :string, default: "en"
    #     # Adds: def copy_locale_files; copy_locales_for("billing"); end
    #   end
    #
    def self.with_locales(namespace)
      self.locale_namespace = namespace
      class_option :locales, type: :string, default: "en",
                             desc: "Comma-separated list of locales"

      define_method(:copy_locale_files) do
        copy_locales_for(namespace)
      end
    end

    # Hook into Thor's invoke_all to auto-copy templates and append agent context.
    # Order:
    # 1. Runs all generator methods (set_options sets instance variables for ERB)
    # 2. Auto-copies templates from mirrored paths (app/, config/, test/, etc.)
    # 3. Validates post-install message format
    # 4. Appends AGENT.md.tt content to CLAUDE.md
    def invoke_all
      resolve_declared_env_options
      super
      copy_mirrored_templates
      validate_post_install_message_format
      append_agent_context
    end

    private

    # Resolve every option_with_env declaration and assign the matching @<name>.
    # Runs at the top of invoke_all so all step methods and ERB templates see the
    # resolved values without needing a custom set_options method.
    def resolve_declared_env_options
      self.class.declared_env_options.each do |spec|
        value = option_with_fallback(spec[:name],
                                     env: spec[:env],
                                     prompt: spec[:prompt],
                                     default: spec[:default])
        value = spec[:transform].call(value) if spec[:transform]
        instance_variable_set("@#{spec[:name]}", value)
      end
    end

    # Auto-copy templates that mirror their destination paths.
    # templates/app/helpers/foo.rb.tt → app/helpers/foo.rb
    def copy_mirrored_templates
      templates_path = self.class.source_root
      return unless File.directory?(templates_path)

      Dir.glob("#{templates_path}/{app,config,test,lib,db,public,docs}/**/*.tt").sort.each do |source|
        relative = source.sub("#{templates_path}/", "")
        next if excluded_template?(relative)

        destination = relative.chomp(".tt")
        template relative, destination
      end
    end

    # Check if template matches any exclusion pattern (class-level or runtime)
    def excluded_template?(relative_path)
      all_exclusions = self.class.template_exclusions + (@runtime_exclusions || [])
      all_exclusions.any? { |pattern| File.fnmatch?(pattern, relative_path, File::FNM_PATHNAME) }
    end

    # Instance method for runtime exclusions based on options
    def exclude_template(pattern)
      @runtime_exclusions ||= []
      @runtime_exclusions << pattern
    end

    def append_agent_context
      agent_template = File.join(self.class.source_root, "AGENT.md.tt")
      return unless File.exist?(agent_template)

      claude_md = "CLAUDE.md"
      return unless File.exist?(File.join(destination_root, claude_md))

      content = ERB.new(File.read(agent_template), trim_mode: "-").result(binding)
      append_to_file claude_md, "\n#{content}"
    end
  end
end
