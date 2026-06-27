require "test_helper"

class OpencodePermissionBridgeFlowTest < ActionDispatch::IntegrationTest
  test "json bridge flow asks, polls pending, decides, and polls resolved" do
    run = create_run
    root = create_passport(run: run, actor_ref: "baris", actor_name: "Baris", actor_kind: "human", provider: "local")
    agent = create_passport(run: run, actor_ref: "main-agent", actor_name: "opencode/main-agent", parent: root, rules: { bash: "ask" })

    post runtime_events_path,
      params: {
        runtime_event: {
          run_id: run.id,
          event_id: "json-bridge-flow-tool-1",
          type: "tool.requested",
          actor_ref: agent.actor_ref,
          capability: "bash",
          action_kind: "bash",
          action_summary: "bash: bin/rails test",
          command: "bin/rails test",
          risk_level: "medium",
          risk_summary: "Runs test suite",
          suggested_capability: "bash",
          suggested_pattern: "bin/rails test"
        }
      },
      headers: bridge_headers(run),
      as: :json

    assert_response :created
    ask_body = JSON.parse(response.body)
    assert_equal true, ask_body.fetch("ok")
    assert_equal "ToolAction", ask_body.fetch("type")
    assert_equal "asking", ask_body.fetch("status")

    permission_request = PermissionRequest.find(ask_body.fetch("permission_request_id"))
    assert_equal permission_request_url(permission_request), ask_body.fetch("permission_request_url")

    get permission_request_path(permission_request), headers: bridge_headers(run), as: :json

    assert_response :success
    pending_body = JSON.parse(response.body)
    assert_equal true, pending_body.fetch("ok")
    assert_equal "pending", pending_body.fetch("status")
    assert_nil pending_body["decision"]
    assert_equal "asking", pending_body.fetch("tool_action_status")

    post permission_request_decisions_path(permission_request),
      params: { decision: { scope: "allow_once" } },
      as: :json

    assert_response :success
    decision_body = JSON.parse(response.body)
    assert_equal true, decision_body.fetch("ok")
    assert_equal "resolved", decision_body.fetch("status")
    assert_equal "allow_once", decision_body.fetch("decision")
    assert_equal "allowed", decision_body.fetch("tool_action_status")

    get permission_request_path(permission_request), headers: bridge_headers(run), as: :json

    assert_response :success
    resolved_body = JSON.parse(response.body)
    assert_equal "resolved", resolved_body.fetch("status")
    assert_equal "allow_once", resolved_body.fetch("decision")
    assert_equal "allowed", resolved_body.fetch("tool_action_status")
  end
end
