class Grant < ApplicationRecord
  belongs_to :passport
  belongs_to :permission_request, optional: true

  validates :capability, :pattern, :effect, :scope, presence: true
  validates :capability, inclusion: { in: Passport::CAPABILITIES }
  validates :effect, inclusion: { in: %w[allow] }
  validates :scope, inclusion: { in: %w[passport] }
  validates :pattern, uniqueness: { scope: [ :passport_id, :capability, :effect ] }
  validate :parent_authority_allows_grant

  private

  def parent_authority_allows_grant
    return if passport.blank? || passport.parent.blank?
    return if passport.parent.authorization_for(capability, pattern) == "allow"

    errors.add(:capability, "cannot exceed parent passport")
  end
end
