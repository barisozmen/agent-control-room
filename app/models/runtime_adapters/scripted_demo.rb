module RuntimeAdapters
  class ScriptedDemo
    def self.start!(runtime_name:, project_path:, cli: nil)
      runtime = RuntimeAdapters::Registry.fetch(runtime_name)
      cli ||= default_cli(runtime)
      run = nil

      run = Run.transaction do
        Run.active.find_each { |active_run| active_run.update!(status: "interrupted", finished_at: Time.current) }

        Run.create!(
          runtime_name: runtime.name,
          project_path: project_path,
          mode: "demo",
          status: "starting",
          started_at: Time.current
        )
      end

      cli.start_demo!(run: run)
      new(run, runtime).seed!
      run
    rescue RuntimeAdapters::CliProcess::Unavailable => error
      fail_run!(run, error.message)
    end

    def self.default_cli(runtime)
      return RuntimeAdapters::CliProcess::Noop.new if Rails.env.test?

      runtime.cli_class_name.constantize.new
    end

    def self.fail_run!(run, message)
      run.update!(status: "failed", finished_at: Time.current, error_message: message)
      AuditEvent.create!(
        run: run,
        event_kind: "adapter.process_failed",
        result: "failed",
        action_summary: message,
        occurred_at: Time.current
      )
      run
    end

    private_class_method :default_cli, :fail_run!

    def initialize(run, runtime)
      @run = run
      @runtime = runtime
      @sequence = 0
    end

    def seed!
      emit("session.started")

      delegate("baris", nil, "Baris", "human", "local", "Local project owner", allow_all)
      delegate("main-agent", "baris", runtime.main_agent_name, "agent", runtime.provider, "Implement the Agent Control Room demo with #{runtime.label}", allow_all)
      delegate("code-writer", "main-agent", "code-writer", "agent", runtime.provider, "Patch the Rails app for the demo", rules(read: "allow", edit: "ask", bash: "ask", web: "ask", delegate: "deny"))
      delegate("security-auditor", "main-agent", "security-auditor", "agent", runtime.provider, "Review the prototype for runtime permission risks", rules(read: "allow", edit: "deny", bash: "ask", web: "ask", delegate: "allow"))
      delegate("docs-writer", "main-agent", "docs-writer", "agent", runtime.provider, "Keep the demo narrative tight", rules(read: "allow", edit: "ask", bash: "deny", web: "ask", delegate: "deny"))
      delegate("dependency-scanner", "security-auditor", "dependency-scanner", "agent", runtime.provider, "Inspect dependency and lockfile risk", rules(read: "allow", edit: "deny", bash: "ask", web: "ask", delegate: "deny"))
      delegate("auth-reviewer", "security-auditor", "auth-reviewer", "agent", runtime.provider, "Review auth-adjacent code paths", rules(read: "allow", edit: "deny", bash: "ask", web: "ask", delegate: "deny"))

      tool("docs-writer", "read", "file_read", "Read README.md and demo docs", path: "README.md", risk_level: "low", risk_summary: "Reads local project text")
      tool("dependency-scanner", "read", "file_read", "Read Gemfile.lock for dependency names", path: "Gemfile.lock", risk_level: "low", risk_summary: "Reads dependency metadata")
      tool("code-writer", "edit", "file_edit", "Patch app/models/user.rb with a demo-safe change", path: "app/models/user.rb", risk_level: "medium", risk_summary: "Would edit project files", suggested_pattern: "app/models/user.rb")
      tool("security-auditor", "bash", "shell_command", "Run bundle exec brakeman", command: "bundle exec brakeman", risk_level: "medium", risk_summary: "Executes local code and reads project files", suggested_pattern: "bundle exec brakeman*")
      tool("auth-reviewer", "web", "shell_command", "Fetch external auth guidance with curl", command: "curl https://example.com/security", risk_level: "high", risk_summary: "Requests network access from a nested subagent", suggested_pattern: "curl https://example.com/security")
    end

    private

    attr_reader :run, :runtime

    def delegate(actor_ref, parent_actor_ref, actor_name, actor_kind, provider, task, ruleset)
      emit(
        "actor.delegated",
        actor_ref: actor_ref,
        parent_actor_ref: parent_actor_ref,
        actor_name: actor_name,
        actor_kind: actor_kind,
        provider: provider,
        task: task,
        rules: ruleset
      )
    end

    def tool(actor_ref, capability, action_kind, action_summary, command: nil, path: nil, risk_level:, risk_summary:, suggested_pattern: nil)
      emit(
        "tool.requested",
        actor_ref: actor_ref,
        capability: capability,
        action_kind: action_kind,
        action_summary: action_summary,
        command: command,
        path: path,
        risk_level: risk_level,
        risk_summary: risk_summary,
        suggested_capability: capability,
        suggested_pattern: suggested_pattern
      )
    end

    def emit(type, **payload)
      @sequence += 1
      CanonicalRuntimeEvents::Processor.new(
        run: run,
        event: {
          event_id: "demo-#{runtime.name}-#{run.id}-#{@sequence}",
          type: type,
          runtime_name: runtime.name,
          run_id: run.id,
          occurred_at: (@sequence.seconds.from_now).iso8601
        }.merge(payload)
      ).process
    end

    def allow_all
      rules(read: "allow", edit: "allow", bash: "allow", web: "allow", delegate: "allow")
    end

    def rules(read:, edit:, bash:, web:, delegate:)
      { read: read, edit: edit, bash: bash, web: web, delegate: delegate }
    end
  end
end
