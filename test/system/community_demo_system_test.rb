require "application_system_test_case"

class CommunityDemoSystemTest < ApplicationSystemTestCase
  test "presenter starts the demo and resolves the permission story" do
    visit root_path

    within("[data-testid='empty-start-panel']") do
      click_button "OpenCode demo"
    end

    assert_selector "turbo-frame#passport_tree", text: "opencode/main-agent"
    assert_selector "turbo-frame#passport_tree", text: "code-writer"
    assert_selector "turbo-frame#passport_tree", text: "security-auditor"
    assert_selector "turbo-frame#passport_tree", text: "dependency-scanner"
    assert_selector "turbo-frame#passport_tree", text: "auth-reviewer"
    assert_selector "turbo-frame#passport_tree", text: "docs-writer"
    assert_selector "turbo-frame#permission_inbox", text: "Ask 1 of 3"

    click_button "Allow once"
    assert_selector "turbo-frame#permission_inbox", text: "Ask 1 of 2"

    click_button "Add to passport"
    assert_selector "turbo-frame#permission_inbox", text: "Ask 1 of 1"

    click_button "Deny"
    assert_selector "turbo-frame#permission_inbox", text: "No pending asks"
    assert_text "completed"

    click_link "Receipts"

    assert_selector "turbo-frame#audit_timeline", text: "session.finished"
    assert_selector "turbo-frame#audit_timeline", text: "permission.decided"
    assert_selector "turbo-frame#audit_timeline", text: "deny"
  end
end
