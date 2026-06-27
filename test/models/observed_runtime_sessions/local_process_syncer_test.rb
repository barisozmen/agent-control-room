require "test_helper"

class ObservedRuntimeSessions::LocalProcessSyncerTest < ActiveSupport::TestCase
  FakeScanner = Struct.new(:sessions)

  test "imports scanner sessions through the generic observed runtime ingestor" do
    event = {
      type: "session.started",
      event_id: "codex-process-4242-started",
      session_id: "codex-process-4242",
      title: "Codex: agent_control_room",
      project_path: Rails.root.to_s,
      pid: 4242,
      occurred_at: Time.current.iso8601
    }

    assert_difference -> { Run.where(runtime_name: "codex").count }, 1 do
      ObservedRuntimeSessions::LocalProcessSyncer.sync!(scanners: [ FakeScanner.new([ event ]) ])
    end

    run = Run.find_by!(runtime_name: "codex", runtime_session_id: "codex-process-4242")

    assert_equal "observed", run.mode
    assert_equal "running", run.status
    assert_equal 4242, run.observed_pid
    assert_equal "codex/main-agent", run.passports.find_by!(actor_ref: "main-agent").actor_name

    assert_no_difference -> { Run.where(runtime_name: "codex").count } do
      ObservedRuntimeSessions::LocalProcessSyncer.sync!(scanners: [ FakeScanner.new([ event ]) ])
    end
  end
end
