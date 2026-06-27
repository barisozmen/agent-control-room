class AuditEvent < ApplicationRecord
  belongs_to :run
  belongs_to :passport, optional: true
  belongs_to :tool_action, optional: true
  belongs_to :permission_request, optional: true

  validates :event_kind, :result, :occurred_at, presence: true
  validates :source_event_id, uniqueness: { scope: :run_id, allow_nil: true }

  scope :chronological, -> { order(:occurred_at, :id) }
end
