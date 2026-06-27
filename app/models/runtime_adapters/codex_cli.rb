module RuntimeAdapters
  class CodexCli < CliProcess
    Unavailable = CliProcess::Unavailable
    Noop = CliProcess::Noop

    DEMO_PROMPT = <<~PROMPT.squish
      Run the Agent Control Room demo task for this local repository. Inspect
      README.md and docs/requirements.md, keep tool use minimal, and do not
      modify files. The Rails control room is observing this Codex process.
    PROMPT

    def initialize(command: nil, **options)
      runtime = RuntimeAdapters::Registry.fetch("codex")
      super(
        runtime: runtime,
        command: command || ENV.fetch(runtime.command_env_key, runtime.default_command),
        demo_args: [ "exec", "--json", "--sandbox", "read-only", "--ask-for-approval", "never", DEMO_PROMPT ],
        **options
      )
    end
  end
end
