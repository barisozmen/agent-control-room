module RuntimeAdapters
  class Registry
    Runtime = Data.define(:name, :label, :provider, :command_env_key, :default_command, :main_agent_name, :observed_task, :cli_class_name)

    CONFIGS = [
      Runtime.new(
        name: "opencode",
        label: "OpenCode",
        provider: "opencode",
        command_env_key: "AGENT_PASSPORTS_OPENCODE",
        default_command: "opencode",
        main_agent_name: "opencode/main-agent",
        observed_task: "Observed OpenCode session",
        cli_class_name: "RuntimeAdapters::OpencodeCli"
      ),
      Runtime.new(
        name: "claude_code",
        label: "Claude Code",
        provider: "claude_code",
        command_env_key: "AGENT_PASSPORTS_CLAUDE_CODE",
        default_command: "claude",
        main_agent_name: "claude-code/main-agent",
        observed_task: "Observed Claude Code session",
        cli_class_name: "RuntimeAdapters::ClaudeCodeCli"
      ),
      Runtime.new(
        name: "codex",
        label: "Codex",
        provider: "codex",
        command_env_key: "AGENT_PASSPORTS_CODEX",
        default_command: "codex",
        main_agent_name: "codex/main-agent",
        observed_task: "Observed Codex session",
        cli_class_name: "RuntimeAdapters::CodexCli"
      ),
      Runtime.new(
        name: "pi",
        label: "Pi",
        provider: "pi",
        command_env_key: "AGENT_PASSPORTS_PI",
        default_command: "pi",
        main_agent_name: "pi/main-agent",
        observed_task: "Observed Pi session",
        cli_class_name: "RuntimeAdapters::PiCli"
      )
    ].index_by(&:name).freeze

    ALIASES = {
      "open_code" => "opencode",
      "claude" => "claude_code",
      "claude-code" => "claude_code",
      "claude_code" => "claude_code",
      "codex_cli" => "codex",
      "pi_coding_agent" => "pi",
      "pi-cli" => "pi",
      "pi_cli" => "pi"
    }.freeze

    def self.fetch(name)
      key = normalize_name(name)
      CONFIGS.fetch(key) { raise ArgumentError, "Unsupported runtime: #{name}" }
    end

    def self.normalize_name(name)
      raw = name.to_s.presence || "opencode"
      normalized = raw.downcase.tr(" ", "_")
      ALIASES.fetch(normalized, normalized)
    end

    def self.options
      CONFIGS.values
    end

    def self.names
      CONFIGS.keys
    end
  end
end
