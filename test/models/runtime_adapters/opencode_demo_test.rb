require "test_helper"

class RuntimeAdapters::OpencodeDemoTest < ActiveSupport::TestCase
  class RecordingCli
    attr_reader :run

    def start_demo!(run:)
      @run = run
      1234
    end
  end

  class FailingCli
    def start_demo!(run:)
      raise RuntimeAdapters::OpencodeCli::Unavailable, "opencode missing"
    end
  end

  test "starts the required community demo hierarchy" do
    run = demo_run

    assert_equal 7, run.passports.count
    assert_equal 6, run.passports.where(actor_kind: "agent").count
    assert_equal 3, run.permission_requests.where(status: "pending").count

    main_agent = run.passports.find_by!(actor_ref: "main-agent")
    assert_equal %w[code-writer security-auditor docs-writer], main_agent.children.pluck(:actor_ref)

    security_auditor = run.passports.find_by!(actor_ref: "security-auditor")
    assert_equal %w[dependency-scanner auth-reviewer], security_auditor.children.pluck(:actor_ref)
    assert run.audit_events.where(event_kind: "permission.requested").exists?
  end

  test "starts opencode before seeding the deterministic demo events" do
    cli = RecordingCli.new

    run = RuntimeAdapters::OpencodeDemo.start!(project_path: Rails.root.to_s, opencode_cli: cli)

    assert_equal run, cli.run
    assert_equal "running", run.status
    assert run.audit_events.where(event_kind: "session.started").exists?
  end

  test "records setup failure when opencode cannot start" do
    run = RuntimeAdapters::OpencodeDemo.start!(project_path: Rails.root.to_s, opencode_cli: FailingCli.new)

    assert_equal "failed", run.status
    assert_equal "opencode missing", run.error_message
    assert_equal 0, run.passports.count
    assert run.audit_events.where(event_kind: "adapter.process_failed", result: "failed").exists?
  end
end
