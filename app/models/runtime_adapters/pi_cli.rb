module RuntimeAdapters
  class PiCli < CliProcess
    Unavailable = CliProcess::Unavailable
    Noop = CliProcess::Noop

    DEMO_PROMPT = <<~PROMPT.squish
      Run the Agent Identity Control Room demo task for this local repository. Inspect
      README.md and docs/requirements.md, keep tool use read-only, and do not
      modify files. The Rails control room is observing this Pi process.
    PROMPT

    def initialize(command: nil, **options)
      runtime = RuntimeAdapters::Registry.fetch("pi")
      super(
        runtime: runtime,
        command: command || ENV.fetch(runtime.command_env_key, runtime.default_command),
        demo_args: [ "--mode", "json", "--no-session", "--no-approve", "--tools", "read,grep,find,ls", "--name", "Agent Identity Control Room demo", DEMO_PROMPT ],
        **options
      )
    end

    private

    def ingest_process_log!(run)
      RuntimeAdapters::PiRunLogIngestor.new(run: run, path: log_path(run)).process
    end
  end
end
