require "test_helper"

class AuditEventTest < ActiveSupport::TestCase
  test "chronological orders by occurred time then id" do
    run = create_run
    later = run.audit_events.create!(event_kind: "later", result: "ok", occurred_at: 1.minute.from_now)
    earlier = run.audit_events.create!(event_kind: "earlier", result: "ok", occurred_at: Time.current)

    assert_equal [ earlier, later ], run.audit_events.chronological.to_a
  end

  test "source event id is unique within a run when present" do
    run = create_run
    run.audit_events.create!(source_event_id: "event-1", event_kind: "first", result: "ok", occurred_at: Time.current)

    duplicate = run.audit_events.build(source_event_id: "event-1", event_kind: "second", result: "ok", occurred_at: Time.current)

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:source_event_id], "has already been taken"
  end

  test "audit events without source ids append as distinct receipts" do
    run = create_run

    assert_difference -> { run.audit_events.count }, 2 do
      run.audit_events.create!(event_kind: "first", result: "ok", occurred_at: Time.current)
      run.audit_events.create!(event_kind: "second", result: "ok", occurred_at: Time.current)
    end
  end
end
