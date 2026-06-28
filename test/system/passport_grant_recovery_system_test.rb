require "application_system_test_case"

class PassportGrantRecoverySystemTest < ApplicationSystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [390, 844] do |options|
    options.add_argument("--disable-dev-shm-usage")
    options.add_argument("--disable-gpu")
    options.add_argument("--no-sandbox")
    options.add_argument("--force-prefers-reduced-motion")
  end

  test "passport drawer lets the user revoke a persistent grant" do
    run = demo_run
    request = run.permission_requests.joins(:passport).find_by!(passports: { actor_ref: "security-auditor" })
    request.resolve!("passport")
    passport = request.passport

    visit run_path(run, passport_id: passport.id, panel: "passport")

    within("turbo-frame#passport_detail") do
      assert_selector "[data-testid='passport-grant']", text: "bundle exec brakeman*"
      accept_confirm "Revoke this passport grant? Future matching actions will ask again." do
        click_button "Revoke grant"
      end
    end

    assert_current_path run_path(run, passport_id: passport.id, panel: "passport"), ignore_query: false

    within("turbo-frame#passport_detail") do
      assert_text "no local grants"
      assert_no_selector "[data-testid='passport-grant']"
      assert_no_button "Revoke grant"
    end

    assert_nil request.reload.grant
    assert run.audit_events.where(event_kind: "permission.grant_revoked", result: "revoked").exists?
  end
end
