class Run < ApplicationRecord
  STATUSES = %w[starting running completed interrupted failed].freeze
  MODES = %w[demo manual observed].freeze

  has_many :passports, dependent: :destroy
  has_many :tool_actions, dependent: :destroy
  has_many :permission_requests, dependent: :destroy
  has_many :audit_events, dependent: :destroy

  validates :runtime_name, :project_path, :mode, :status, presence: true
  validates :bridge_token, presence: true, uniqueness: true
  validates :status, inclusion: { in: STATUSES }
  validates :mode, inclusion: { in: MODES }

  before_validation :ensure_bridge_token, on: :create

  scope :latest_first, -> { order(created_at: :desc, id: :desc) }
  scope :session_list, -> { order(Arel.sql("COALESCE(last_seen_at, started_at, created_at) DESC"), created_at: :desc, id: :desc) }
  scope :active, -> { where(status: %w[starting running]) }

  def self.current
    active.latest_first.first || latest_first.first
  end

  def active?
    status.in?(%w[starting running])
  end

  def failed?
    status == "failed"
  end

  def root_passport
    passports.find_by(parent_id: nil)
  end

  def selected_passport(passport_id = nil)
    passports.find_by(id: passport_id) || passports.find_by(actor_ref: "security-auditor") || passports.find_by(actor_ref: "main-agent") || root_passport
  end

  def display_title
    title.presence || "#{runtime_name} #{id}"
  end

  def display_project
    Pathname.new(project_path).basename.to_s
  rescue StandardError
    project_path
  end

  def broadcast_control_room!(selected_passport: nil)
    selected_passport ||= self.selected_passport

    broadcast_replace_to self, target: "session_sidebar", partial: "runs/session_sidebar", locals: { runs: Run.session_list, selected_run: self }
    broadcast_replace_to self, target: "run_header", partial: "runs/run_header", locals: { run: self }
    broadcast_replace_to self, target: "passport_tree", partial: "runs/passport_tree", locals: { run: self, selected_passport: selected_passport }
    broadcast_replace_to self, target: "permission_inbox", partial: "runs/permission_inbox", locals: { run: self }
    broadcast_replace_to self, target: "audit_timeline", partial: "runs/audit_timeline", locals: { run: self, audit_events: audit_events.chronological }
    broadcast_replace_to "opencode_sessions", target: "session_sidebar", partial: "runs/session_sidebar", locals: { runs: Run.session_list, selected_run: nil }

    return unless selected_passport.present?

    broadcast_replace_to self, target: "passport_detail", partial: "runs/passport_detail", locals: { run: self, passport: selected_passport }
  end

  private

  def ensure_bridge_token
    self.bridge_token ||= SecureRandom.urlsafe_base64(32)
  end
end
