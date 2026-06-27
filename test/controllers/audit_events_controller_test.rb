require "test_helper"

class AuditEventsControllerTest < ActionDispatch::IntegrationTest
  test "full page audit requests redirect to the run audit drawer" do
    run = create_run

    get run_audit_events_path(run)

    assert_redirected_to run_path(run, panel: "audit")
  end

  test "turbo frame audit requests render the receipt timeline" do
    run = create_run
    owner = create_passport(run: run, actor_ref: "baris", actor_name: "Baris", actor_kind: "human", provider: "local")
    passport = create_passport(run: run, actor_ref: "auth-reviewer", actor_name: "auth-reviewer", parent: owner)
    event = run.audit_events.create!(
      passport: passport,
      event_kind: "tool.allowed",
      actor_lineage: passport.lineage_label,
      capability: "web",
      action_summary: "Fetch external auth guidance",
      result: "allowed",
      occurred_at: Time.current
    )

    get run_audit_events_path(run), headers: { "Turbo-Frame" => "audit_timeline" }

    assert_response :success
    assert_select "turbo-frame#audit_timeline"
    assert_select "h2", text: "Receipt drawer"
    assert_select "span", text: "tool.allowed"
    assert_select "span", text: "web"
    assert_select "p", text: "Fetch external auth guidance"
    assert_select "li##{dom_id(event)}"
    assert_select "a[href='#{run_path(run, passport_id: passport.id, panel: "passport")}'][data-turbo-frame='_top']", text: passport.lineage_label
    assert_select "div", text: "allowed"
  end
end
