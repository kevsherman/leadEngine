module Gmail
  class Importer
    def initialize(connection, client: Client.new(connection))
      @connection, @client = connection, client
      @authorization_version = connection.authorization_version
    end

    def import_id(id)
      return if Message.exists?(provider_id: provider_id(id))
      process(@client.message(id))
    rescue NotFound
      nil # A message deleted during synchronization is not a lost inquiry.
    end

    def process(metadata)
      envelope = Envelope.new(metadata)
      id = metadata.fetch("id")
      return unless envelope.safe_labels?
      return if envelope.own_sender? && !Array(metadata["labelIds"]).include?("SENT")
      return if Message.exists?(provider_id: provider_id(id))
      # A polled app-originated send is reconciled, never imported as a second reply.
      own_operation = SendOperation.find_by(gmail_connection: @connection, rfc_message_id: envelope.message_id) if envelope.message_id
      if own_operation && envelope.sender == GmailConnection::SALES_ADDRESS && envelope.recipients.include?(own_operation.payload.fetch("to"))
        Gmail::Delivery.record!(own_operation, metadata)
        return
      end
      conversation = linked_conversation(envelope)
      form = nil
      if envelope.form_candidate?(@connection)
        full = @client.message(id, format: "full")
        form = ShopifyForm.parse(Content.read(full.fetch("payload")), envelope)
        return review(envelope, "shopify_customer_identity_uncertain") unless form
        conversation = @connection_conversations.where(gmail_thread_id: metadata["threadId"], customer_email: form[:email]).first
      elsif @connection.sender_addresses.include?(envelope.sender) || envelope.sender.match?(/@(?:shopify\.com|shopifyemail\.com)\z/i)
        return review(envelope, "unrecognized_shopify_notification") if envelope.sales_addressed?
        return
      elsif conversation == :ambiguous
        return
      elsif conversation
        full = @client.message(id, format: "full")
      elsif envelope.sales_addressed? && !envelope.own_sender? && envelope.sender.present? && !envelope.sender.match?(/\A(?:no-?reply|notifications?)@/i)
        full = @client.message(id, format: "full")
      else
        return
      end
      persist(envelope, full, conversation, form)
    rescue MalformedMessage => error
      review(envelope, error.code) if envelope
    end

    def import_review(item, email:, name:)
      raise AuthorizationError.new("connect_gmail_first") unless @connection.authorized?
      full = @client.message(item.provider_message_id, format: "full")
      envelope = Envelope.new(full)
      persist(envelope, full, nil, { email: email, name: name, body: Content.read(full.fetch("payload")), fields: { "identity_confirmed_by_operator" => true } })
      item.update!(resolved: true)
    end

    private

    def provider_id(id)
      "gmail:#{@connection.id}:#{id}"
    end

    def linked_conversation(envelope)
      @connection_conversations = Conversation.where(gmail_connection: @connection)
      by_thread = @connection_conversations.where(gmail_thread_id: envelope.data["threadId"]).to_a
      by_reference = Message.where(gmail_connection: @connection, rfc_message_id: envelope.reference_ids).includes(:conversation).map(&:conversation)
      candidates = (by_reference.presence || by_thread).uniq.select do |conversation|
        if envelope.own_sender?
          envelope.recipients.include?(conversation.customer_email)
        else
          envelope.sender == conversation.customer_email && (envelope.recipients & [ GmailConnection::MAILBOX, GmailConnection::SALES_ADDRESS ]).any?
        end
      end
      return candidates.first if candidates.size == 1
      if candidates.size > 1 || ((by_thread + by_reference).any? && candidates.empty?)
        review(envelope, "ambiguous_project_thread")
        return :ambiguous
      end
      nil
    end

    def persist(envelope, full, conversation, form)
      @connection.with_lock do
        raise AuthorizationError.new("connection_changed_during_import") unless @connection.authorized? && @connection.authorization_version == @authorization_version
        return if Message.exists?(provider_id: provider_id(full.fetch("id")))
        if conversation
          conversation.lock!
        else
          email = form ? form[:email] : envelope.sender
          conversation = Conversation.create!(source_id: "gmail-inquiry:#{@connection.id}:#{full.fetch('id')}", gmail_connection: @connection,
            email_provider: "gmail", gmail_thread_id: full.fetch("threadId"), customer_name: form ? form[:name] : email,
            customer_email: email, subject: envelope.subject, project: envelope.subject, category: form ? "Contact form" : "Sales inquiry",
            known_fields: form ? form[:fields] : {}, status: "needs_review", next_action: "Read inquiry and prepare reply", last_activity_at: received_at(full))
        end
        outbound = envelope.own_sender? && !form
        message = conversation.messages.create!(gmail_connection: @connection, provider_id: provider_id(full.fetch("id")),
          provider_thread_id: full.fetch("threadId"), rfc_message_id: envelope.message_id, references_header: envelope.reference_ids,
          sender: envelope.sender, recipient: envelope.addresses("To").join(", "), cc: envelope.addresses("Cc").join(", "),
          reply_to: form ? form[:email] : envelope.addresses("Reply-To").join(", "), subject: envelope.subject,
          body: form ? form[:body] : Content.read(full.fetch("payload")), direction: outbound ? "outbound" : "inbound",
          attachments: Content.attachments(full.fetch("payload")), created_at: received_at(full))
        draft = conversation.email_draft
        if draft&.status == "approved"
          draft.update!(status: "editing", approved_by: nil, approved_at: nil, approved_message_id: nil,
            approval_provider: nil, approval_connection_version: nil)
        end
        if !outbound && (draft.nil? || %w[sent blocked cancelled].include?(draft.status))
          conversation.create_email_draft!(to: conversation.customer_email, subject: reply_subject(envelope.subject),
            body: "Hi #{conversation.customer_name},

[Write your reply here.]

Best,
Kevin
Breeze Block Canada")
        end
        conversation.update!(last_activity_at: [ conversation.last_activity_at, message.created_at ].max,
          status: outbound ? "waiting_for_customer" : "needs_review", next_action: outbound ? "Wait for customer reply" : "Review customer message and draft")
        conversation.audit_events.create!(action: outbound ? "gmail_operator_reply_imported" : "gmail_customer_message_imported")
        GmailReviewItem.where(gmail_connection: @connection, provider_message_id: full.fetch("id")).update_all(resolved: true)
      end
    end

    def received_at(data)
      Time.at(data.fetch("internalDate").to_i / 1000.0).in_time_zone
    end

    def reply_subject(subject)
      subject.match?(/\ARe:/i) ? subject : "Re: #{subject}"
    end

    def review(envelope, reason)
      @connection.gmail_review_items.find_or_create_by!(provider_message_id: envelope.data.fetch("id")) do |item|
        item.thread_id = envelope.data.fetch("threadId")
        item.reason = reason
      end
      nil
    end
  end
end
