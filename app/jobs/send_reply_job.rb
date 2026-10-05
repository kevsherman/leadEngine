class SendReplyJob < ApplicationJob
  queue_as :default

  def perform(operation_id)
    operation = SendOperation.find(operation_id)
    operation.with_lock do
      return if %w[sent blocked cancelled].include?(operation.status)
      draft = operation.email_draft
      receipt = Providers::FakeEmail.new.deliver(operation)
      draft.conversation.messages.create!(direction: "outbound", sender: operation.payload.fetch("from"),
        recipient: operation.payload.fetch("to"), subject: operation.payload.fetch("subject"),
        body: operation.payload.fetch("body"), provider_id: receipt.provider_message_id)
      operation.update!(status: "sent", error: nil)
      draft.update!(status: "sent")
      draft.conversation.update!(status: "waiting_for_customer", next_action: "Wait for customer reply", last_activity_at: Time.current)
      draft.conversation.audit_events.create!(action: "fake_email_delivered", details: receipt.provider_message_id)
    end
  rescue StandardError => error
    operation&.update!(status: "failed", error: error.class.name)
    operation&.email_draft&.update!(status: "failed")
    raise
  end
end
