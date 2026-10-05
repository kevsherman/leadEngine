require "base64"
require "mail"

module Gmail
  class Delivery
    def self.raw(operation)
      payload = operation.payload
      mail = Mail.new
      mail.from = GmailConnection::SALES_ADDRESS
      mail.reply_to = GmailConnection::SALES_ADDRESS
      mail.to = payload.fetch("to")
      mail.cc = payload["cc"] if payload["cc"].present?
      mail.subject = payload.fetch("subject")
      mail.message_id = operation.rfc_message_id.delete_prefix("<").delete_suffix(">")
      mail.in_reply_to = payload["in_reply_to"] if payload["in_reply_to"].present?
      mail.references = payload["references"] if payload["references"].present?
      mail.date = operation.created_at
      mail.content_type = "text/plain; charset=UTF-8"
      mail.body = payload.fetch("body")
      Base64.urlsafe_encode64(mail.encoded, padding: false)
    end

    def self.record!(operation, result)
      operation.with_lock do
        return if operation.status == "sent"
        conversation = operation.email_draft.conversation
        conversation.lock!
        provider_id = "gmail:#{operation.gmail_connection_id}:#{result.fetch('id')}"
        message = Message.find_or_initialize_by(provider_id: provider_id)
        if message.new_record?
          message.assign_attributes(conversation: conversation, gmail_connection_id: operation.gmail_connection_id,
            provider_thread_id: result.fetch("threadId"), rfc_message_id: operation.rfc_message_id,
            direction: "outbound", sender: GmailConnection::SALES_ADDRESS, recipient: operation.payload.fetch("to"),
            cc: operation.payload["cc"], reply_to: GmailConnection::SALES_ADDRESS, subject: operation.payload.fetch("subject"),
            references_header: operation.payload.fetch("references", []), body: operation.payload.fetch("body"))
          message.save!
        end
        operation.update!(status: "sent", provider_message_id: result.fetch("id"), provider_thread_id: result.fetch("threadId"), error: nil)
        operation.email_draft.update!(status: "sent")
        # Preserve actionable inbound mail that arrived after the approved snapshot.
        newer_inbound = conversation.messages.where(direction: "inbound").where("id > ?", operation.email_draft.approved_message_id).exists?
        conversation.update!(status: newer_inbound ? "needs_review" : "waiting_for_customer",
          next_action: newer_inbound ? "Review new customer reply" : "Wait for customer reply", last_activity_at: Time.current)
        conversation.audit_events.create!(action: "gmail_email_delivered", details: result.fetch("id"))
      end
    end
  end
end
