require "test_helper"
require "fileutils"

class RuntimeAdapters::PiSessionLogScannerTest < ActiveSupport::TestCase
  setup do
    @pi_home = Pathname.new(Dir.mktmpdir("pi-home"))
    @session_path = @pi_home.join("sessions", "--tmp-project--", "20260627_pi-session-1.jsonl")
  end

  teardown do
    FileUtils.remove_entry(@pi_home)
  end

  test "marks the newest pi session for an active project as running" do
    write_records(
      { type: "session", version: 3, id: "pi-session-1", timestamp: "2026-06-27T17:36:49Z", cwd: Rails.root.to_s },
      { type: "message", id: "entry-1", timestamp: "2026-06-27T17:36:50Z", message: { role: "assistant", content: [ { type: "toolCall", id: "call-1", name: "read", arguments: { path: "README.md" } } ] } }
    )

    events = RuntimeAdapters::PiSessionLogScanner.new(
      pi_home: @pi_home,
      active_project_paths: [ Rails.root.to_s ]
    ).sessions

    assert_equal [ "session.started", "tool.observed" ], events.map { |event| event.fetch(:type) }
    assert_equal "pi-session-1", events.first.fetch(:session_id)
    assert_equal "Pi: agent_control_room", events.first.fetch(:title)
    assert_equal Rails.root.to_s, events.first.fetch(:project_path)
    assert_equal "README.md", events.second.fetch(:path)
  end

  test "marks pi session logs completed when no process is active for the project" do
    write_records(
      { type: "session", version: 3, id: "pi-session-2", timestamp: "2026-06-27T17:36:49Z", cwd: Rails.root.to_s }
    )

    events = RuntimeAdapters::PiSessionLogScanner.new(
      pi_home: @pi_home,
      active_project_paths: []
    ).sessions

    assert_equal [ "session.started", "session.finished" ], events.map { |event| event.fetch(:type) }
    assert_equal "completed", events.last.fetch(:status)
    assert_equal "pi-session-log-pi-session-2-finished", events.last.fetch(:event_id)
  end

  test "skips malformed pi session metadata" do
    write_file("{")

    assert_equal [], RuntimeAdapters::PiSessionLogScanner.new(pi_home: @pi_home).sessions
  end

  private

  def write_records(*records)
    write_file(records.map { |record| JSON.generate(record) }.join("\n") + "\n")
  end

  def write_file(content)
    FileUtils.mkdir_p(@session_path.dirname)
    File.write(@session_path, content)
  end
end
