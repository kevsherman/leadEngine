require "base64"

module GmailFixtures
  def create_gmail_connection
    @connection = GmailConnection.create!(mailbox: GmailConnection::MAILBOX, client_id: "test-client",
      client_secret: "synthetic-secret", access_token: "synthetic-access", refresh_token: "synthetic-refresh",
      expires_at: 1.hour.from_now, status: "connected", polling_enabled: true, import_since: 14.days.ago.to_date,
      sending_enabled: true, alias_confirmed: true, alias_verified_at: Time.current)
  end

  def gmail_message(id: "m1", thread: "thread1", from: "Morgan <morgan@example.test>", to: GmailConnection::SALES_ADDRESS,
    subject: "Courtyard inquiry", body: "Please quote 80 blocks.", reply_to: nil, reference: nil, labels: [ "INBOX" ], timestamp: Time.current)
    headers = { "From" => from, "To" => to, "Subject" => subject, "Message-ID" => "<#{id}@example.test>" }
    headers["Reply-To"] = reply_to if reply_to
    headers["References"] = reference if reference
    headers["In-Reply-To"] = reference if reference
    { "id" => id, "threadId" => thread, "internalDate" => (timestamp.to_f * 1000).to_i.to_s, "labelIds" => labels,
      "payload" => { "mimeType" => "text/plain", "headers" => headers.map { |name, value| { "name" => name, "value" => value } },
        "body" => { "data" => Base64.urlsafe_encode64(body), "size" => body.bytesize } } }
  end

  class Client
    attr_reader :calls, :sent_count
    attr_accessor :messages, :history_pages, :history_error, :send_error, :send_result, :list_pages, :profile_result, :alias_result
    def initialize(messages = {})
      @messages = messages
      @calls = []
      @sent_count = 0
      @profile_result = { "emailAddress" => GmailConnection::MAILBOX, "historyId" => "100" }
      @history_pages = { nil => { "historyId" => "200", "history" => [] } }
      @list_pages = {}
      @alias_result = { "sendAsEmail" => GmailConnection::SALES_ADDRESS, "verificationStatus" => "accepted" }
      @send_result = { "id" => "sent1", "threadId" => "thread1" }
    end
    def message(id, format: "metadata")
      @calls << [ :message, id, format ]
      result = @messages.fetch(id) { raise Gmail::NotFound.new }
      return result if format == "full"
      result.deep_dup.tap { |value| value["payload"].delete("body") }
    end
    def profile
      @profile_result
    end
    def list_messages(query:, page_token: nil)
      @calls << [ :list, query, page_token ]
      @list_pages.fetch(page_token) { { "messages" => @messages.keys.map { |id| { "id" => id } } } }
    end
    def history(start_id:, page_token: nil)
      @calls << [ :history, start_id, page_token ]
      raise @history_error if @history_error
      @history_pages.fetch(page_token)
    end
    def thread(id)
      @calls << [ :thread, id ]
      { "messages" => @messages.values.select { |message| message["threadId"] == id } }
    end
    def token
      "synthetic-access"
    end
    def alias_settings
      @alias_result
    end
    def send_message(raw:, thread_id:)
      @sent_count += 1
      @calls << [ :send, raw, thread_id ]
      raise @send_error if @send_error
      @send_result
    end
  end
end
