require "test_helper"

class PermissionRequestTest < ActiveSupport::TestCase
  test "passport decision creates a scoped grant and receipt" do
    run = demo_run
    request = run.permission_requests.joins(:passport).find_by!(passports: { actor_ref: "security-auditor" })

    assert_difference -> { Grant.count }, 1 do
      assert_difference -> { AuditEvent.where(event_kind: "permission.decided").count }, 1 do
        request.resolve!("passport")
      end
    end

    assert_equal "resolved", request.reload.status
    assert_equal "passport_grant", request.decision
    assert_equal "allowed", request.tool_action.status
    assert_equal "bundle exec brakeman*", request.grant.pattern
  end

  test "allow once resolves without a passport grant" do
    run = demo_run
    request = run.permission_requests.joins(:passport).find_by!(passports: { actor_ref: "code-writer" })

    assert_no_difference -> { Grant.count } do
      request.resolve!("allow_once")
    end

    assert_equal "allow_once", request.reload.decision
    assert_equal "allowed", request.tool_action.status
  end

  test "resolved permission request cannot be decided again" do
    run = demo_run
    request = run.permission_requests.joins(:passport).find_by!(passports: { actor_ref: "code-writer" })
    request.resolve!("allow_once")
    decided_at = request.reload.decided_at

    assert_no_difference -> { AuditEvent.where(permission_request: request, event_kind: "permission.decided").count } do
      assert_raises(ArgumentError) { request.resolve!("deny") }
    end

    assert_equal "allow_once", request.reload.decision
    assert_equal decided_at.to_i, request.decided_at.to_i
    assert_equal "allowed", request.tool_action.reload.status
  end

  test "bridge payload and grant pattern use the visible scoped request state" do
    run = demo_run
    request = run.permission_requests.joins(:passport).find_by!(passports: { actor_ref: "security-auditor" })

    assert_equal "bash", request.suggested_grant_capability
    assert_equal "bundle exec brakeman*", request.suggested_grant_pattern
    assert_equal(
      {
        ok: true,
        id: request.id,
        status: "pending",
        decision: nil,
        tool_action_id: request.tool_action_id,
        tool_action_status: "asking"
      },
      request.bridge_payload
    )
  end
end
