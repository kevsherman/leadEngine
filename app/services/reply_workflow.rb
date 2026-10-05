# Approval and send authority belong here, never in a provider or drafting tool.
class ReplyWorkflow
  class InvalidTransition < StandardError; end

  def self.approve(draft, operator, version)
    draft.with_lock do
      check_version!(draft, version)
      raise InvalidTransition, "Only an editable reply can be approved." unless draft.editable?
      raise InvalidTransition, "Write your reply before approving it." if draft.body.include?("[Write your reply here.]")
      draft.update!(status: "approved", approved_by: operator, approved_at: Time.current,
        approved_message_id: draft.conversation.messages.last&.id,
        approval_provider: draft.conversation.email_provider,
        approval_connection_version: draft.conversation.gmail_connection&.authorization_version)
      draft.conversation.audit_events.create!(action: "draft_approved", operator: operator)
    end
  end

  def self.enqueue(draft, operator, version, confirm_live: false)
    operation = nil
    live = draft.conversation.email_provider == "gmail"
    raise InvalidTransition, "Confirm live sending of the approved reply first." if live && !confirm_live
    draft.with_lock do
      # Repeated submission reuses the same operation and its immutable content.
      operation = draft.send_operation
      if operation && %w[sending unknown blocked cancelled].include?(operation.status)
        raise InvalidTransition, "This send must be reconciled or replaced by a newly reviewed draft."
      end
      if live
        connection = draft.conversation.gmail_connection
        raise InvalidTransition, "Connect Gmail and verify the sales alias before sending." unless connection&.live_send_ready?
        raise InvalidTransition, "The Gmail connection changed. Approve this saved reply again." unless draft.approval_provider == "gmail" && draft.approval_connection_version == connection.authorization_version
      end
      unless operation
        check_version!(draft, version)
        raise InvalidTransition, "Approve the exact saved reply first." unless draft.status == "approved"
        raise InvalidTransition, "A new message arrived. Review and approve again." unless draft.approved_message_id == draft.conversation.messages.last&.id
        operation = draft.create_send_operation!(status: "queued", payload: {
          from: "sales@breezeblock.ca", reply_to: "sales@breezeblock.ca", to: draft.to,
          cc: draft.cc, subject: draft.subject, body: draft.body, attachments: [],
          in_reply_to: live ? draft.conversation.messages.last&.rfc_message_id : draft.conversation.messages.last&.provider_id,
          references: live ? (draft.conversation.messages.last.references_header + [ draft.conversation.messages.last.rfc_message_id ]).compact.uniq : [],
          thread_id: draft.conversation.messages.last&.provider_thread_id || draft.conversation.gmail_thread_id
        })
        if live
          operation.update!(provider: "gmail", gmail_connection: connection, authorization_version: connection.authorization_version,
            rfc_message_id: "<inquiry-#{SecureRandom.uuid}@breezeblock.ca>", requested_by_id: operator.id)
        end
        draft.update!(status: "queued")
        draft.conversation.audit_events.create!(action: live ? "gmail_send_requested" : "fake_send_requested", operator: operator)
      end
    end
    job = operation.provider == "gmail" ? GmailSendJob : SendReplyJob
    job.perform_later(operation.id) unless operation.status == "sent"
    operation
  rescue ActiveJob::EnqueueError, SolidQueue::Job::EnqueueError
    raise InvalidTransition, "The worker queue is unavailable. Your approved reply is safely stored; retry the explicitly requested send."
  end

  def self.check_version!(draft, version)
    raise InvalidTransition, "This draft changed. Reload and review the latest version." unless version.to_s == draft.lock_version.to_s
  end
end
