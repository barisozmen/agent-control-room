require "test_helper"

class PermissionRequestsControllerTest < ActionDispatch::IntegrationTest
  test "shows pending request status as json for runtime bridges" do
    run = demo_run
    request = run.permission_requests.pending.first

    get permission_request_path(request), headers: bridge_headers(run), as: :json

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal true, body.fetch("ok")
    assert_equal request.id, body.fetch("id")
    assert_equal "pending", body.fetch("status")
    assert_nil body["decision"]
    assert_equal request.tool_action_id, body.fetch("tool_action_id")
    assert_equal "asking", body.fetch("tool_action_status")
  end

  test "shows resolved decision as json for runtime bridges" do
    run = demo_run
    request = run.permission_requests.pending.first
    request.resolve!("allow_once")

    get permission_request_path(request), headers: bridge_headers(run), as: :json

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "resolved", body.fetch("status")
    assert_equal "allow_once", body.fetch("decision")
    assert_equal "allowed", body.fetch("tool_action_status")
  end

  test "returns json not found for unknown request ids" do
    get permission_request_path(PermissionRequest.maximum(:id).to_i + 1), as: :json

    assert_response :not_found
    body = JSON.parse(response.body)
    assert_equal false, body.fetch("ok")
    assert_match "Couldn't find PermissionRequest", body.fetch("error")
  end

  test "rejects polling without bridge token" do
    run = demo_run
    request = run.permission_requests.pending.first

    get permission_request_path(request), as: :json

    assert_response :unauthorized
    body = JSON.parse(response.body)
    assert_equal false, body.fetch("ok")
    assert_equal "Invalid bridge token", body.fetch("error")
  end
end
