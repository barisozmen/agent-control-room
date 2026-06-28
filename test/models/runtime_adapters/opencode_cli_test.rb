require "test_helper"

class RuntimeAdapters::OpencodeCliTest < ActiveSupport::TestCase
  FakeProcess = Struct.new(:spawn_args, :detached_pid) do
    def spawn(*args)
      self.spawn_args = args
      4242
    end

    def detach(pid)
      self.detached_pid = pid
    end
  end

  FakeStatus = Struct.new(:exitstatus, :termsig, :signaled_process, keyword_init: true) do
    def success?
      exitstatus == 0 && !signaled?
    end

    def signaled?
      signaled_process
    end
  end

  SynchronousMonitor = Struct.new(:status, :watched_pid) do
    def watch(pid)
      self.watched_pid = pid
      yield status
    end
  end

  test "starts opencode run with json events and adapter environment" do
    run = create_run
    process = FakeProcess.new
    cli = RuntimeAdapters::OpencodeCli.new(command: "opencode-test", process: process, check_available: false)

    assert_equal 4242, cli.start_demo!(run: run)

    env = process.spawn_args.first
    options = process.spawn_args.last

    assert_equal "opencode-test", process.spawn_args[1]
    assert_equal "run", process.spawn_args[2]
    assert_equal "json", process.spawn_args[process.spawn_args.index("--format") + 1]
    assert_equal "Agent Identity Control Room demo", process.spawn_args[process.spawn_args.index("--title") + 1]
    assert_equal run.id.to_s, env.fetch("AGENT_PASSPORTS_RUN_ID")
    assert_equal run.bridge_token, env.fetch("AGENT_PASSPORTS_BRIDGE_TOKEN")
    assert_equal "http://127.0.0.1:#{expected_runtime_events_port}/runtime_events", env.fetch("AGENT_PASSPORTS_RUNTIME_EVENTS_URL")
    assert_equal run.project_path, options.fetch(:chdir)
    assert_match %r{log/opencode-demo-run-#{run.id}\.log\z}, options.fetch(:out)
    assert_equal [ :child, :out ], options.fetch(:err)
    assert_equal 4242, process.detached_pid
    assert run.audit_events.where(event_kind: "adapter.process_started", result: "started").exists?
  end

  test "raises a setup error when opencode is unavailable" do
    run = create_run
    cli = RuntimeAdapters::OpencodeCli.new(command: "/definitely/missing/opencode", check_available: true)

    error = assert_raises(RuntimeAdapters::OpencodeCli::Unavailable) do
      cli.start_demo!(run: run)
    end

    assert_includes error.message, "opencode"
  end

  test "records successful process completion" do
    run = create_run
    process = FakeProcess.new
    monitor = SynchronousMonitor.new(FakeStatus.new(exitstatus: 0, signaled_process: false))
    cli = RuntimeAdapters::OpencodeCli.new(command: "opencode-test", process: process, check_available: false, monitor: monitor)

    cli.start_demo!(run: run)

    assert_equal 4242, monitor.watched_pid
    assert_equal "completed", run.reload.status
    assert_not run.error_message.present?
    assert run.audit_events.where(event_kind: "adapter.process_finished", result: "completed").exists?
  end

  test "records failed process completion" do
    run = create_run
    monitor = SynchronousMonitor.new(FakeStatus.new(exitstatus: 2, signaled_process: false))
    cli = RuntimeAdapters::OpencodeCli.new(command: "opencode-test", process: FakeProcess.new, check_available: false, monitor: monitor)

    cli.start_demo!(run: run)

    assert_equal "failed", run.reload.status
    assert_includes run.error_message, "exit 2"
    assert run.audit_events.where(event_kind: "adapter.process_finished", result: "failed").exists?
  end

  test "records interrupted process completion" do
    run = create_run
    monitor = SynchronousMonitor.new(FakeStatus.new(termsig: 15, signaled_process: true))
    cli = RuntimeAdapters::OpencodeCli.new(command: "opencode-test", process: FakeProcess.new, check_available: false, monitor: monitor)

    cli.start_demo!(run: run)

    assert_equal "interrupted", run.reload.status
    assert_includes run.error_message, "signal 15"
    assert run.audit_events.where(event_kind: "adapter.process_finished", result: "interrupted").exists?
  end

  private

    def expected_runtime_events_port
      ENV["PORT"].presence || Rails.root.join("bin/find_server_port").then { |script| IO.popen([ script.to_s ], &:read).to_s.strip }
    end
end
