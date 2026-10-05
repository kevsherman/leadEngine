class Conversation < ApplicationRecord
  belongs_to :gmail_connection, optional: true
  has_many :email_drafts, dependent: :destroy
  has_many :messages, -> { order(:created_at, :id) }, dependent: :destroy
  has_many :audit_events, dependent: :destroy
  validates :email_provider, inclusion: { in: %w[fake gmail] }

  def email_draft
    email_drafts.order(:id).last
  end

  def create_email_draft!(**attributes)
    email_drafts.create!(**attributes)
  end

  validates :customer_name, :customer_email, :subject, :next_action, presence: true
  validates :status, inclusion: { in: %w[needs_review waiting_for_customer] }

  def self.queue(search: nil, status: nil)
    scope = order(:last_activity_at, :id)
    scope = scope.where(status: status) if %w[needs_review waiting_for_customer].include?(status)
    if search.present?
      query = "%#{sanitize_sql_like(search)}%"
      scope = scope.where("customer_name ILIKE :q OR customer_email ILIKE :q OR subject ILIKE :q OR project ILIKE :q", q: query)
    end
    scope
  end
end
