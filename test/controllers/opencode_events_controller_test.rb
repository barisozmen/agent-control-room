require "test_helper"

class OpencodeEventsControllerTest < ActionDispatch::IntegrationTest
  test "rejects observer events without machine token" do
    post opencode_events_path,
      params: { opencode_event: { type: "session.started", session_id: "missing-token" } },
      as: :json

    assert_response :unauthorized
    assert_equal false, JSON.parse(response.body).fetch("ok")
  end

  test "creates an observed opencode session and base passports" do
    assert_difference -> { Run.count }, 1 do
      post_observer_event(
        type: "session.started",
        event_id: "observed-session-started",
        session_id: "observed-session-1",
        title: "Observed repo",
        project_path: Rails.root.to_s,
        pid: 12345
      )
    end

    assert_response :created
    body = JSON.parse(response.body)
    run = Run.find(body.fetch("run_id"))

    assert_equal "observed", run.mode
    assert_equal "observed-session-1", run.runtime_session_id
    assert_equal "Observed repo", run.title
    assert_equal 12345, run.observed_pid
    assert_equal "running", run.status
    assert_equal [ "local-owner", "main-agent" ], run.passports.order(:id).pluck(:actor_ref)
  end

  test "tool request creates an observed action and pending permission request" do
    post_observer_event(
      type: "tool.requested",
      event_id: "observed-tool-1",
      session_id: "observed-session-2",
      title: "Observed tools",
      project_path: Rails.root.to_s,
      actor_ref: "main-agent",
      capability: "bash",
      action_kind: "bash",
      action_summary: "bash: bin/rails test",
      command: "bin/rails test",
      risk_level: "medium",
      risk_summary: "Runs tests",
      suggested_capability: "bash",
      suggested_pattern: "bin/rails test"
    )

    assert_response :created
    body = JSON.parse(response.body)
    run = Run.find(body.fetch("run_id"))
    action = run.tool_actions.find_by!(source_event_id: "observed-tool-1")

    assert_equal "asking", action.status
    assert_equal run.permission_requests.last.id, body.fetch("permission_request_id")
    assert_match %r{/permission_requests/#{body.fetch("permission_request_id")}\z}, body.fetch("permission_request_url")
  end

  test "machine token can poll observed permission requests" do
    post_observer_event(
      type: "tool.requested",
      event_id: "observed-tool-poll",
      session_id: "observed-session-3",
      title: "Observed poll",
      project_path: Rails.root.to_s,
      capability: "bash",
      action_kind: "bash",
      action_summary: "bash: ruby -v",
      command: "ruby -v"
    )

    request = PermissionRequest.order(id: :desc).first

    get permission_request_path(request), headers: machine_bridge_headers, as: :json

    assert_response :success
    assert_equal "pending", JSON.parse(response.body).fetch("status")
  end

  private

  def post_observer_event(event)
    post opencode_events_path,
      params: { opencode_event: event },
      headers: machine_bridge_headers,
      as: :json
  end
end
