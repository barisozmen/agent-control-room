class PermissionRequest < ApplicationRecord
  STATUSES = %w[pending resolved].freeze
  RISK_LEVELS = %w[low medium high].freeze
  DECISIONS = %w[allow_once passport_grant deny].freeze

  belongs_to :run
  belongs_to :passport
  belongs_to :tool_action

  has_one :grant, dependent: :nullify
  has_many :audit_events, dependent: :nullify

  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :risk_level, inclusion: { in: RISK_LEVELS }, allow_blank: true
  validates :decision, inclusion: { in: DECISIONS }, allow_blank: true
  validates :tool_action_id, uniqueness: true
  validate :decision_state_is_consistent

  scope :pending, -> { where(status: "pending").order(created_at: :desc, id: :desc) }
  scope :resolved, -> { where(status: "resolved").order(decided_at: :desc, id: :desc) }

  def resolve!(scope)
    normalized_scope = scope.to_s
    decision_value = normalized_scope == "passport" ? "passport_grant" : normalized_scope
    raise ArgumentError, "Unknown decision scope" unless DECISIONS.include?(decision_value)

    transaction do
      lock!
      raise ArgumentError, "Permission request already resolved" if resolved?

      update!(status: "resolved", decision: decision_value, decided_at: Time.current)

      if decision_value == "passport_grant"
        create_or_find_passport_grant!
        tool_action.update!(status: "allowed")
      elsif decision_value == "allow_once"
        tool_action.update!(status: "allowed")
      else
        tool_action.update!(status: "denied", finished_at: Time.current)
      end

      append_decision_receipt!
    end
  end

  def resolved?
    status == "resolved"
  end

  def suggested_grant_capability
    suggested_capability.presence || tool_action.capability
  end

  def suggested_grant_pattern
    suggested_pattern.presence || tool_action.request_text
  end

  def bridge_payload
    {
      ok: true,
      id: id,
      status: status,
      decision: decision,
      tool_action_id: tool_action_id,
      tool_action_status: tool_action.status
    }
  end

  private

  def decision_state_is_consistent
    if status == "pending" && (decision.present? || decided_at.present?)
      errors.add(:decision, "must be blank while pending")
    elsif status == "resolved" && (decision.blank? || decided_at.blank?)
      errors.add(:decision, "and decided_at are required when resolved")
    end
  end

  def create_or_find_passport_grant!
    grant_record = Grant.find_or_create_by!(
      passport: passport,
      capability: suggested_grant_capability,
      pattern: suggested_grant_pattern,
      effect: "allow",
      scope: "passport"
    )
    grant_record.update!(permission_request: self) if grant_record.permission_request.blank?
    grant_record
  end

  def append_decision_receipt!
    AuditEvent.create!(
      run: run,
      passport: passport,
      tool_action: tool_action,
      permission_request: self,
      event_kind: "permission.decided",
      actor_lineage: passport.lineage_label,
      capability: tool_action.capability,
      action_summary: tool_action.action_summary,
      decision: decision,
      result: decision == "deny" ? "denied" : "allowed",
      occurred_at: Time.current
    )
  end
end
