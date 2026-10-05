class SendOperation < ApplicationRecord
  belongs_to :email_draft
  belongs_to :gmail_connection, optional: true
  has_one :fake_delivery, dependent: :destroy
  validates :email_draft_id, uniqueness: true
  validates :status, inclusion: { in: %w[queued sending failed sent unknown blocked cancelled] }
end
