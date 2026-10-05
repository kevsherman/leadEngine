class EmailDraft < ApplicationRecord
  belongs_to :conversation
  belongs_to :approved_by, class_name: "Operator", optional: true
  has_one :send_operation, dependent: :destroy
  validates :to, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :subject, :body, presence: true
  validate :valid_cc
  validates :status, inclusion: { in: %w[editing approved queued failed sent unknown blocked cancelled] }
  before_update :protect_reviewed_content

  def editable?
    %w[editing approved].include?(status)
  end

  private

  def valid_cc
    return if cc.blank?
    errors.add(:cc, "must contain comma-separated email addresses") unless cc.split(",").all? { |address| URI::MailTo::EMAIL_REGEXP.match?(address.strip) }
  end

  def protect_reviewed_content
    if %w[to cc subject body].any? { |field| will_save_change_to_attribute?(field) }
      if %w[queued failed sent unknown blocked cancelled].include?(status_in_database)
        errors.add(:base, "A queued or sent reply cannot be edited")
        throw :abort
      end
      self.status = "editing"
      self.approved_at = self.approved_by_id = self.approved_message_id = nil
      self.approval_provider = self.approval_connection_version = nil
    end
  end
end
