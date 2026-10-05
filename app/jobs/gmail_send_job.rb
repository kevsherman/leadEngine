class GmailSendJob < ApplicationJob
  # A live send is never automatically retried. A claimed/crashed operation reconciles first.
  def perform(operation_id)
    operation = SendOperation.find(operation_id)
    return unless operation.provider == "gmail"
    reconcile = false
    operation.with_lock do
      return if %w[sent blocked cancelled].include?(operation.status)
      if %w[sending unknown].include?(operation.status)
        reconcile = true
      else
        draft = operation.email_draft
        conversation = draft.conversation
        conversation.lock!
        connection = operation.gmail_connection
        unless connection.live_send_ready? && connection.authorization_version == operation.authorization_version
          fail_operation!(operation, "blocked", "gmail_connection_changed_review_again")
          return
        end
        unless draft.approved_message_id == conversation.messages.last&.id && draft.approved_at.present?
          fail_operation!(operation, "blocked", "new_message_requires_review")
          return
        end
        operation.update!(status: "sending", error: nil) # COMMIT before making the external write.
      end
    end
    if reconcile
      GmailReconcileJob.perform_later(operation.id)
      return
    end
    connection = operation.gmail_connection
    client = Gmail::Client.new(connection)
    # Authentication/alias failures occur before POST and are safe to mark rejected.
    client.token
    alias_settings = client.alias_settings
    raise Gmail::Error.new("sales_alias_not_accepted") unless alias_settings["verificationStatus"] == "accepted" && alias_settings["sendAsEmail"] == GmailConnection::SALES_ADDRESS
    result = client.send_message(raw: Gmail::Delivery.raw(operation), thread_id: operation.payload.fetch("thread_id"))
    raise Gmail::UncertainWrite.new("gmail_send_outcome_unknown") unless result["id"].present? && result["threadId"].present?
    Gmail::Delivery.record!(operation, result)
  rescue Gmail::UncertainWrite => error
    fail_operation!(operation, "unknown", error.code)
  rescue Gmail::Error => error
    fail_operation!(operation, "failed", error.code)
    connection&.failure!(error)
  rescue StandardError
    # Includes database failure after Gmail accepted a message: never lose uncertain outcomes.
    fail_operation!(operation, "unknown", "gmail_send_outcome_unknown") if operation
  end

  private

  def fail_operation!(operation, status, error)
    operation.with_lock do
      return if operation.status == "sent"
      operation.update!(status: status, error: error)
      operation.email_draft.update!(status: status)
      operation.email_draft.conversation.audit_events.create!(action: "gmail_send_#{status}", details: error)
    end
  end
end
