require "test_helper"

class GrantsControllerTest < ActionDispatch::IntegrationTest
  test "turbo stream revoke removes passport grant and refreshes recovery surfaces" do
    run = demo_run
    request = run.permission_requests.joins(:passport).find_by!(passports: { actor_ref: "security-auditor" })
    request.resolve!("passport")
    grant = request.grant

    assert_turbo_stream_broadcasts run, count: 7 do
      assert_difference -> { Grant.count }, -1 do
        assert_difference -> { AuditEvent.where(event_kind: "permission.grant_revoked").count }, 1 do
          delete run_passport_grant_path(run, request.passport, grant), headers: { "Accept" => Mime[:turbo_stream].to_s }
        end
      end
    end

    assert_response :success
    assert_equal "text/vnd.turbo-stream.html", response.media_type
    assert_not Grant.exists?(grant.id)
    assert_select "turbo-stream[action='replace'][target='passport_detail']"
    assert_select "turbo-stream[action='replace'][target='audit_timeline']"
    assert_select "turbo-stream[action='replace'][target='tool_action_list']"
    assert_includes response.body, "no local grants"
    assert_includes response.body, "permission.grant_revoked"
    assert_includes response.body, "Passport grant revoked"
  end

  test "html revoke returns user to passport drawer" do
    run = demo_run
    request = run.permission_requests.joins(:passport).find_by!(passports: { actor_ref: "security-auditor" })
    request.resolve!("passport")
    grant = request.grant

    delete run_passport_grant_path(run, request.passport, grant)

    assert_redirected_to run_path(run, passport_id: request.passport_id, panel: "passport")
    follow_redirect!

    assert_response :success
    assert_select "turbo-frame#passport_detail" do
      assert_select "h3", text: "local grants"
      assert_select "p", text: "no local grants"
      assert_select "button", text: "Revoke grant", count: 0
    end
    assert_select "turbo-frame#flash_messages", text: /Passport grant revoked/
  end
end
