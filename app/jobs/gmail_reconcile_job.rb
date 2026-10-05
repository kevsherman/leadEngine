class GmailReconcileJob < ApplicationJob
  def perform(operation_id)
    operation = SendOperation.find(operation_id)
    return unless operation.provider == "gmail" && %w[sending unknown].include?(operation.status)
    connection = operation.gmail_connection
    raise Gmail::AuthorizationError.new("reconnect_before_reconciliation") unless connection.authorized?
    client = Gmail::Client.new(connection)
    query = "in:sent rfc822msgid:#{operation.rfc_message_id.delete_prefix('<').delete_suffix('>')}"
    result = client.list_messages(query: query)
    if Array(result["messages"]).one?
      message = client.message(result.fetch("messages").first.fetch("id"))
      envelope = Gmail::Envelope.new(message)
      if Array(message["labelIds"]).include?("SENT") && envelope.message_id == operation.rfc_message_id && envelope.sender == GmailConnection::SALES_ADDRESS && envelope.recipients.include?(operation.payload.fetch("to"))
        Gmail::Delivery.record!(operation, message)
        return
      end
    end
    operation.with_lock do
      unless operation.status == "sent"
        operation.update!(status: "unknown", error: "not_yet_found_in_sent_mail")
        operation.email_draft.update!(status: "unknown")
      end
    end
  rescue Gmail::Error => error
    connection&.failure!(error)
    operation&.update!(error: error.code) unless operation&.status == "sent"
  end
end
