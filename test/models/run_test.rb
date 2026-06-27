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

  test "session list is capped to the recent session window" do
    runs = 55.times.map do |index|
      Run.create!(
        runtime_name: "opencode",
        project_path: Rails.root.to_s,
        mode: "demo",
        status: "completed",
        started_at: index.minutes.ago,
        finished_at: index.minutes.ago,
        created_at: index.minutes.ago
      )
    end

    listed_runs = Run.session_list.to_a

    assert_equal Run::SESSION_LIST_LIMIT, listed_runs.size
    assert_includes listed_runs, runs.first
    assert_not_includes listed_runs, runs.last
  end

  test "pending permission counts are fetched in one grouped query" do
    first_run = create_run
    second_run = create_run
    resolved_only_run = create_run

    2.times { create_permission_request_for(first_run) }
    create_permission_request_for(second_run)
    create_permission_request_for(resolved_only_run, status: "resolved")

    counts = nil
    queries = permission_request_sql_queries do
      counts = Run.pending_permission_request_counts_for([ first_run, second_run, resolved_only_run ])
    end

    assert_equal({ first_run.id => 2, second_run.id => 1 }, counts)
    assert_equal 1, queries.size, queries.join("\n")
    assert_match(/GROUP BY/i, queries.first)
  end

  test "session sidebar partial renders pending counts without per-run permission queries" do
    runs = [ create_run, create_run, create_run ]
    2.times { create_permission_request_for(runs.first) }
    create_permission_request_for(runs.second)
    locals = Run.session_sidebar_locals(selected_run: runs.first)

    html = nil
    queries = permission_request_sql_queries do
      html = ApplicationController.renderer.render(partial: "runs/session_sidebar", locals: locals)
    end

    assert_match(/ap-count-pill[^>]*>2</, html)
    assert_match(/ap-count-pill[^>]*>1</, html)
    assert_empty queries
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

  def create_permission_request_for(run, status: "pending")
    passport = run.passports.first || create_passport(
      run: run,
      actor_ref: "owner",
      actor_name: "Owner",
      actor_kind: "human",
      provider: "local"
    )
    tool_action = run.tool_actions.create!(
      passport: passport,
      capability: "bash",
      action_kind: "command",
      status: "asking",
      requested_at: Time.current,
      command: "echo #{SecureRandom.hex(4)}"
    )
    attributes = {
      passport: passport,
      tool_action: tool_action,
      status: status
    }
    attributes.merge!(decision: "deny", decided_at: Time.current) if status == "resolved"

    run.permission_requests.create!(attributes)
  end

  def permission_request_sql_queries
    queries = []
    subscriber = lambda do |_name, _started, _finished, _id, payload|
      next if payload[:cached]
      next if %w[SCHEMA TRANSACTION].include?(payload[:name])

      sql = payload[:sql]
      queries << sql if sql.match?(/(?:FROM|UPDATE|INSERT INTO|DELETE FROM) "?permission_requests"?/i)
    end

    ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") { yield }
    queries
  end
end
