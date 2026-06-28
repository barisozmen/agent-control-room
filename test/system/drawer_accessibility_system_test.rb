require "application_system_test_case"

class DrawerAccessibilitySystemTest < ApplicationSystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [390, 844] do |options|
    options.add_argument("--disable-dev-shm-usage")
    options.add_argument("--disable-gpu")
    options.add_argument("--no-sandbox")
    options.add_argument("--force-prefers-reduced-motion")
  end

  test "drawer behaves as a modal surface for keyboard users" do
    page.driver.browser.manage.window.resize_to(390, 844)

    run = demo_run
    passport = run.passports.find_by!(actor_ref: "auth-reviewer")

    visit run_path(run, passport_id: passport.id, panel: "passport")

    assert_selector ".ap-drawer[role='dialog'][aria-modal='true'][aria-labelledby='passport-drawer-title']"
    assert_selector "#passport-drawer-title", text: "auth-reviewer"
    assert evaluate_script("document.querySelector('[data-drawer-target=\"background\"]').inert")
    assert_selector ".ap-drawer a.ap-quiet-link:focus", text: "Passport"

    20.times { send_keys(:tab) }

    assert evaluate_script("document.querySelector('.ap-drawer').contains(document.activeElement)")

    send_keys(:escape)

    assert_no_selector ".ap-drawer"
    assert_current_path run_path(run, passport_id: passport.id), ignore_query: false
  end

  test "desktop drawer closes when the developer opens a different session" do
    page.driver.browser.manage.window.resize_to(1280, 900)

    current_run = demo_run
    other_run = Run.create!(
      runtime_name: "opencode",
      runtime_session_id: "session-switch-target",
      title: "Switch target session",
      project_path: Rails.root.to_s,
      mode: "observed",
      status: "running",
      started_at: Time.current,
      last_seen_at: Time.current
    )
    passport = current_run.passports.find_by!(actor_ref: "auth-reviewer")

    visit run_path(current_run, passport_id: passport.id, panel: "audit")

    assert_selector ".ap-drawer[role='dialog'][aria-labelledby='audit-drawer-title']"
    assert_no_selector ".ap-drawer[aria-modal='true']"
    refute evaluate_script("document.querySelector('[data-drawer-target=\"background\"]').inert")

    click_link "Switch target session"

    assert_no_selector ".ap-drawer"
    assert_current_path run_path(other_run), ignore_query: false
    assert_selector "a.ap-session-row[aria-current='page']", text: "Switch target session"
  end
end
