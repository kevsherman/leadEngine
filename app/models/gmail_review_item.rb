class GmailReviewItem < ApplicationRecord
  belongs_to :gmail_connection
  # Only identifiers and a fixed reason are stored; ambiguous bodies stay in Gmail.
end
