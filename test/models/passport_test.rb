require "test_helper"

class PassportTest < ActiveSupport::TestCase
  test "child passport cannot exceed parent authority" do
    run = create_run
    parent = create_passport(run: run, actor_ref: "parent", actor_name: "parent", actor_kind: "human", provider: "local", rules: { edit: "ask" })

    child = run.passports.build(
      parent: parent,
      actor_ref: "child",
      actor_name: "child",
      actor_kind: "agent",
      provider: "opencode",
      status: "active",
      read_rule: "allow",
      edit_rule: "allow",
      bash_rule: "allow",
      web_rule: "allow",
      delegate_rule: "allow"
    )

    assert_not child.valid?
    assert_includes child.errors[:edit_rule], "cannot exceed parent passport"
  end

  test "lineage labels include every parent" do
    run = demo_run
    passport = run.passports.find_by!(actor_ref: "auth-reviewer")

    assert_equal "Baris / opencode/main-agent / security-auditor / auth-reviewer", passport.lineage_label
  end
end
