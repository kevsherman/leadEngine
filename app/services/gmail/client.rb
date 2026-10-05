module Gmail
  class Client
    HEADERS = %w[From To Cc Delivered-To Reply-To Subject Message-ID In-Reply-To References Auto-Submitted].freeze
    ROOT = "https://gmail.googleapis.com/gmail/v1/users/me".freeze

    def initialize(connection, http: Http.new, access_token: nil)
      @connection, @http, @temporary_token = connection, http, access_token
    end

    def profile
      get("profile")
    end

    def alias_settings
      get("settings/sendAs/#{ERB::Util.url_encode(GmailConnection::SALES_ADDRESS)}")
    end

    def list_messages(query:, page_token: nil)
      get("messages", q: query, maxResults: 100, pageToken: page_token)
    end

    def message(id, format: "metadata")
      params = { format: format }
      params[:metadataHeaders] = HEADERS if format == "metadata"
      get("messages/#{ERB::Util.url_encode(id)}", **params)
    end

    def thread(id)
      get("threads/#{ERB::Util.url_encode(id)}", format: "metadata", metadataHeaders: HEADERS)
    end

    def history(start_id:, page_token: nil)
      get("history", startHistoryId: start_id, historyTypes: "messageAdded", maxResults: 100, pageToken: page_token)
    end

    def send_message(raw:, thread_id:)
      @http.request(:post, "#{ROOT}/messages/send", token: token,
        json: { raw: raw, threadId: thread_id }, write: true)
    end

    def token
      return @temporary_token if @temporary_token
      @connection.with_lock do
        raise AuthorizationError.new("google_authorization_required") unless @connection.authorized?
        if @connection.access_token.blank? || @connection.expires_at.blank? || @connection.expires_at < 1.minute.from_now
          result = Oauth.new(@connection, http: @http).refresh
          @connection.update!(access_token: result.fetch("access_token"), expires_at: result.fetch("expires_in", 3600).to_i.seconds.from_now)
        end
        @connection.access_token
      end
    end

    private

    def get(path, **params)
      pairs = params.compact.flat_map { |key, value| Array(value).map { |item| [ key, item ] } }
      url = "#{ROOT}/#{path}"
      url += "?#{URI.encode_www_form(pairs)}" if pairs.any?
      retried = false
      begin
        @http.request(:get, url, token: token)
      rescue AuthorizationError
        raise if retried || @temporary_token
        retried = true
        @connection.update!(expires_at: Time.current)
        retry # One refresh/retry for safe reads only; never retry a send POST.
      end
    end
  end
end
