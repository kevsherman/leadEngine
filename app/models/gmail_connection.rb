class GmailConnection < ApplicationRecord
  MAILBOX = "kevin.sherman@breezeblock.ca"
  SALES_ADDRESS = "sales@breezeblock.ca"
  SCOPES = %w[https://www.googleapis.com/auth/gmail.readonly https://www.googleapis.com/auth/gmail.send].freeze
  encrypts :client_secret, :access_token, :refresh_token
  has_many :gmail_review_items, dependent: :destroy
  validates :mailbox, inclusion: { in: [ MAILBOX ] }, uniqueness: true
  validates :status, inclusion: { in: %w[needs_authorization connected error disabled] }
  validates :poll_interval_seconds, numericality: { only_integer: true, greater_than_or_equal_to: 30, less_than_or_equal_to: 3600 }
  validates :import_since, presence: true
  validate :valid_shopify_senders

  def self.configured
    find_or_create_by!(mailbox: MAILBOX) { |connection| connection.import_since = 14.days.ago.to_date }
  end

  def authorized?
    refresh_token.present? && %w[connected error].include?(status)
  end

  def live_send_ready?
    authorized? && sending_enabled? && alias_confirmed? && alias_verified_at.present?
  end

  def sender_addresses
    shopify_senders.split(",").map { |value| value.strip.downcase }.reject(&:blank?)
  end

  def failure!(error)
    update!(status: error.is_a?(Gmail::AuthorizationError) ? "needs_authorization" : "error", last_error: error.code)
  end

  private

  def valid_shopify_senders
    errors.add(:shopify_senders, "must contain comma-separated email addresses") unless sender_addresses.all? { |value| URI::MailTo::EMAIL_REGEXP.match?(value) }
  end
end
