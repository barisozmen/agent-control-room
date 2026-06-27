require "fileutils"

module RuntimeAdapters
  class OpencodeCli
    class Unavailable < StandardError; end

    class AsyncProcessMonitor
      def initialize(process)
        @process = process
      end

      def watch(pid, &callback)
        waiter = process.detach(pid)
        return unless waiter.respond_to?(:value)

        Thread.new do
          status = waiter.value
          Rails.application.executor.wrap { callback.call(status) }
        rescue StandardError => error
          Rails.logger.error("Failed to record opencode process exit for pid #{pid}: #{error.class}: #{error.message}")
        end
      end

      private

      attr_reader :process
    end

    class Noop
      def start_demo!(run:)
        nil
      end
    end

    DEMO_PROMPT = <<~PROMPT.squish
      Run the Agent Control Room demo task for this local repository. Inspect
      README.md and docs/requirements.md, keep tool use minimal, and do not
      modify files. The Rails control room is observing this opencode process.
    PROMPT

    def initialize(command: ENV.fetch("AGENT_PASSPORTS_OPENCODE", "opencode"), process: Process, check_available: true, monitor: nil)
      @command = command
      @process = process
      @check_available = check_available
      @monitor = monitor || AsyncProcessMonitor.new(process)
    end

    def start_demo!(run:)
      ensure_available!

      pid = process.spawn(
        adapter_environment(run),
        command,
        "run",
        "--format",
        "json",
        "--title",
        "Agent Control Room demo",
        DEMO_PROMPT,
        chdir: run.project_path,
        out: log_path(run).to_s,
        err: [ :child, :out ]
      )
      record_process_started!(run, pid)
      monitor.watch(pid) { |status| record_process_finished!(run.id, pid, status) }
      pid
    rescue Errno::ENOENT => error
      raise Unavailable, error.message
    end

    private

    attr_reader :command, :process, :check_available, :monitor

    def ensure_available!
      return unless check_available
      return if system(command, "--version", out: File::NULL, err: File::NULL)

      raise Unavailable, "`#{command}` is not available. Install opencode or set AGENT_PASSPORTS_OPENCODE."
    rescue Errno::ENOENT
      raise Unavailable, "`#{command}` is not available. Install opencode or set AGENT_PASSPORTS_OPENCODE."
    end

    def adapter_environment(run)
      {
        "AGENT_PASSPORTS_RUN_ID" => run.id.to_s,
        "AGENT_PASSPORTS_BRIDGE_TOKEN" => run.bridge_token,
        "AGENT_PASSPORTS_RUNTIME_EVENTS_URL" => runtime_events_url
      }
    end

    def runtime_events_url
      "http://127.0.0.1:#{server_port}/runtime_events"
    end

    def server_port
      ENV["PORT"].presence || resolved_dev_port || "3000"
    end

    def resolved_dev_port
      script = Rails.root.join("bin/find_server_port")
      return unless script.exist?

      IO.popen([ script.to_s ], &:read).to_s.strip.presence
    rescue StandardError => error
      Rails.logger.warn("Failed to resolve dev server port: #{error.class}: #{error.message}")
      nil
    end

    def log_path(run)
      FileUtils.mkdir_p(Rails.root.join("log"))
      Rails.root.join("log", "opencode-demo-run-#{run.id}.log")
    end

    def record_process_started!(run, pid)
      AuditEvent.create!(
        run: run,
        event_kind: "adapter.process_started",
        result: "started",
        action_summary: "opencode run process started with pid #{pid}",
        occurred_at: Time.current
      )
    end

    def record_process_finished!(run_id, pid, status)
      run = Run.find_by(id: run_id)
      return unless run

      result = process_result(status)
      summary = process_finished_summary(pid, status, result)
      occurred_at = Time.current

      run.with_lock do
        if run.status.in?(%w[starting running])
          attributes = { status: result, finished_at: occurred_at }
          attributes[:error_message] = summary unless result == "completed"
          run.update!(attributes)
        end

        AuditEvent.create!(
          run: run,
          event_kind: "adapter.process_finished",
          result: result,
          action_summary: summary,
          occurred_at: occurred_at
        )
      end

      run.reload.broadcast_control_room!
    end

    def process_result(status)
      return "completed" if status.respond_to?(:success?) && status.success?
      return "interrupted" if status.respond_to?(:signaled?) && status.signaled?

      "failed"
    end

    def process_finished_summary(pid, status, result)
      if status.respond_to?(:exitstatus) && status.exitstatus.present?
        "opencode run process #{result} with pid #{pid} (exit #{status.exitstatus})"
      elsif status.respond_to?(:termsig) && status.termsig.present?
        "opencode run process #{result} with pid #{pid} (signal #{status.termsig})"
      else
        "opencode run process #{result} with pid #{pid}"
      end
    end
  end
end
