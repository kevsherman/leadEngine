ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "minitest/mock"

module WorkflowFixtures
  def create_inquiry
    @operator = Operator.create!(email: "kevin@example.test", password: "test-password")
    @conversation = Conversation.create!(source_id: "test-inquiry", customer_name: "Morgan", customer_email: "morgan@example.test",
      subject: "Courtyard", project: "Vancouver", next_action: "Review draft", last_activity_at: Time.current)
    @conversation.messages.create!(provider_id: "test-message", direction: "inbound", sender: "morgan@example.test", subject: "Courtyard", body: "Please quote 80 blocks.")
    @draft = @conversation.create_email_draft!(to: "morgan@example.test", subject: "Re: Courtyard", body: "Please confirm your delivery address.")
  end
end

class ActiveSupport::TestCase
  include WorkflowFixtures
end
