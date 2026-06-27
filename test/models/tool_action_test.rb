require "test_helper"

class ToolActionTest < ActiveSupport::TestCase
  test "request text prefers command then path then summary" do
    run = create_run
    passport = create_passport(run: run, actor_ref: "root", actor_name: "root", actor_kind: "human", provider: "local")

    command_action = build_action(run: run, passport: passport, command: "bundle exec rails test", path: "Gemfile", action_summary: "Run tests")
    path_action = build_action(run: run, passport: passport, path: "Gemfile", action_summary: "Read Gemfile")
    summary_action = build_action(run: run, passport: passport, action_summary: "Inspect project")

    assert_equal "bundle exec rails test", command_action.request_text
    assert_equal "Gemfile", path_action.request_text
    assert_equal "Inspect project", summary_action.request_text
  end

  test "source event id is unique within a run when present" do
    run = create_run
    passport = create_passport(run: run, actor_ref: "root", actor_name: "root", actor_kind: "human", provider: "local")
    build_action(run: run, passport: passport, source_event_id: "event-1").save!

    duplicate = build_action(run: run, passport: passport, source_event_id: "event-1")

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:source_event_id], "has already been taken"
  end

  private

  def build_action(run:, passport:, source_event_id: nil, command: nil, path: nil, action_summary: "Action")
    run.tool_actions.build(
      passport: passport,
      source_event_id: source_event_id,
      capability: "bash",
      action_kind: "shell_command",
      action_summary: action_summary,
      command: command,
      path: path,
      status: "requested",
      requested_at: Time.current
    )
  end
end
