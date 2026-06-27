require "test_helper"

class GrantTest < ActiveSupport::TestCase
  test "grant cannot exceed parent effective authority" do
    run = create_run
    parent = create_passport(run: run, actor_ref: "parent", actor_name: "parent", actor_kind: "human", provider: "local", rules: { bash: "ask" })
    child = create_passport(run: run, actor_ref: "child", actor_name: "child", parent: parent, rules: { bash: "ask" })

    grant = child.grants.build(capability: "bash", pattern: "bundle exec rails test", effect: "allow", scope: "passport")

    assert_not grant.valid?
    assert_includes grant.errors[:capability], "cannot exceed parent passport"
  end

  test "parent scoped grant can allow matching child scoped grant" do
    run = create_run
    parent = create_passport(run: run, actor_ref: "parent", actor_name: "parent", actor_kind: "human", provider: "local", rules: { bash: "ask" })
    child = create_passport(run: run, actor_ref: "child", actor_name: "child", parent: parent, rules: { bash: "ask" })
    parent.grants.create!(capability: "bash", pattern: "bundle exec*", effect: "allow", scope: "passport")

    grant = child.grants.build(capability: "bash", pattern: "bundle exec rails test", effect: "allow", scope: "passport")

    assert grant.valid?
  end

  test "duplicate grant pattern is rejected for the same passport capability and effect" do
    run = create_run
    passport = create_passport(run: run, actor_ref: "root", actor_name: "root", actor_kind: "human", provider: "local")
    passport.grants.create!(capability: "read", pattern: "README.md", effect: "allow", scope: "passport")

    duplicate = passport.grants.build(capability: "read", pattern: "README.md", effect: "allow", scope: "passport")

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:pattern], "has already been taken"
  end
end
