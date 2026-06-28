require "test_helper"

class RuntimeAdapters::PiJsonlTranslatorTest < ActiveSupport::TestCase
  test "turns pi json mode tool events into canonical observed tool events" do
    translator = RuntimeAdapters::PiJsonlTranslator.new
    session_events = translator.events_for({
      type: "session",
      version: 3,
      id: "pi-session-1",
      timestamp: "2026-06-27T17:36:49Z",
      cwd: Rails.root.to_s
    })
    tool_events = translator.events_for({
      type: "tool_execution_start",
      toolCallId: "call-1",
      toolName: "bash",
      args: { command: "bin/rails test" }
    })
    finish_events = translator.events_for({
      type: "tool_execution_end",
      toolCallId: "call-1",
      toolName: "bash",
      result: { exitCode: 0 },
      isError: false
    })

    assert_equal [ "session.started" ], session_events.map { |event| event.fetch(:type) }

    event = tool_events.sole
    assert_equal "pi", event.fetch(:runtime_name)
    assert_equal "tool.observed", event.fetch(:type)
    assert_equal "pi-session-1", event.fetch(:session_id)
    assert_equal "bash", event.fetch(:capability)
    assert_equal "shell_command", event.fetch(:action_kind)
    assert_equal "bin/rails test", event.fetch(:command)
    assert_equal "pi-jsonl-pi-session-1-call-1-requested", event.fetch(:event_id)

    finished = finish_events.sole
    assert_equal "tool.finished", finished.fetch(:type)
    assert_equal "pi-jsonl-pi-session-1-call-1-requested", finished.fetch(:source_event_id)
    assert_equal 0, finished.fetch(:exit_status)
  end

  test "turns pi session message tool calls into stable events" do
    translator = RuntimeAdapters::PiJsonlTranslator.new(session_id: "pi-session-2", project_path: Rails.root.to_s)

    events = translator.events_for({
      type: "message",
      id: "entry-1",
      timestamp: "2026-06-27T17:36:49Z",
      message: {
        role: "assistant",
        content: [
          { type: "text", text: "Checking files" },
          { type: "toolCall", id: "call-2", name: "read", arguments: { path: "README.md" } }
        ]
      }
    })

    event = events.sole

    assert_equal "tool.observed", event.fetch(:type)
    assert_equal "read", event.fetch(:capability)
    assert_equal "read", event.fetch(:action_kind)
    assert_equal "README.md", event.fetch(:path)
    assert_equal "pi-jsonl-pi-session-2-call-2-requested", event.fetch(:event_id)
  end
end
