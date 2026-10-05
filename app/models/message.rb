class Message < ApplicationRecord
  belongs_to :conversation
  belongs_to :gmail_connection, optional: true
  validates :provider_id, uniqueness: true
  validates :body, :sender, :subject, presence: true
  validates :direction, inclusion: { in: %w[inbound outbound] }
end
