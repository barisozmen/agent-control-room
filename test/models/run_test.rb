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

  test "passport tree snapshot prevents recursive passport queries while rendering" do
    run = create_run
    owner = create_passport(run: run, actor_ref: "baris", actor_name: "Baris", actor_kind: "human", provider: "local")
    main = create_passport(run: run, actor_ref: "main-agent", actor_name: "opencode/main-agent", parent: owner)
    security = create_passport(run: run, actor_ref: "security-auditor", actor_name: "security-auditor", parent: main)
    create_passport(run: run, actor_ref: "dependency-scanner", actor_name: "dependency-scanner", parent: security)
    create_passport(run: run, actor_ref: "auth-reviewer", actor_name: "auth-reviewer", parent: security)

    tree = nil
    snapshot_queries = capture_sql { tree = run.passport_tree }

    assert_equal 1, passport_queries(snapshot_queries).size
    assert_equal security, tree.selected_passport(security.id)
    assert_equal 2, tree.child_count_for(security)
    assert_equal 4, tree.agent_count

    html = nil
    render_queries = capture_sql do
      html = ApplicationController.renderer.render(
        partial: "runs/passport_tree",
        locals: { run: run, selected_passport: security, passport_tree: tree }
      )
    end

    assert_includes html, "4 agents"
    assert_includes html, "2 children"
    assert_includes html, "auth-reviewer"
    assert_empty passport_queries(render_queries)
  end

  private

  def capture_sql(&block)
    queries = []
    subscriber = lambda do |_name, _started, _finished, _unique_id, payload|
      sql = payload[:sql].to_s
      next if payload[:cached]
      next if payload[:name] == "SCHEMA"
      next if sql.match?(/\A(?:BEGIN|COMMIT|ROLLBACK|SAVEPOINT|RELEASE)/i)
      next if sql.match?(/(?:sqlite_master|ar_internal_metadata)/i)

      queries << sql
    end

    ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record", &block)
    queries
  end

  def passport_queries(queries)
    queries.grep(/FROM "?passports"?/i)
  end
end
