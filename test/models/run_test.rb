require "test_helper"

class RunTest < ActiveSupport::TestCase
  test "current prefers active run over latest completed run" do
    active = create_run
    completed = Run.create!(
      runtime_name: "opencode",
      project_path: Rails.root.to_s,
      mode: "demo",
      status: "completed",
      started_at: Time.current,
      finished_at: Time.current,
      created_at: 1.minute.from_now
    )

    assert_equal active, Run.current

    active.update!(status: "completed", finished_at: Time.current)

    assert_equal completed, Run.current
  end

  test "status predicates expose active and failed states" do
    run = create_run

    assert run.active?
    assert_not run.failed?

    run.update!(status: "failed", finished_at: Time.current, error_message: "opencode missing")

    assert_not run.active?
    assert run.failed?
  end

  test "new runs get a bridge token" do
    run = create_run

    assert_predicate run.bridge_token, :present?
    assert_operator run.bridge_token.length, :>=, 32
  end
end
