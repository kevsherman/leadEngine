require "base64"
require "digest"

module Gmail
  class Oauth
    def self.redirect_uri
      ENV.fetch("GMAIL_REDIRECT_URI", "http://127.0.0.1:3000/gmail/callback")
    end

    def initialize(connection, http: Http.new)
      @connection, @http = connection, http
    end

    def authorize_url(state:, verifier:)
      raise Error.new("oauth_credentials_missing") if @connection.client_id.blank? || @connection.client_secret.blank?
      params = { client_id: @connection.client_id, redirect_uri: self.class.redirect_uri, response_type: "code",
        scope: GmailConnection::SCOPES.join(" "), access_type: "offline", prompt: "consent",
        state: state, login_hint: GmailConnection::MAILBOX, hd: "breezeblock.ca",
        code_challenge: Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false), code_challenge_method: "S256" }
      "https://accounts.google.com/o/oauth2/v2/auth?#{URI.encode_www_form(params)}"
    end

    def exchange(code:, verifier:)
      @http.request(:post, "https://oauth2.googleapis.com/token", form: {
        code: code, code_verifier: verifier, client_id: @connection.client_id, client_secret: @connection.client_secret,
        redirect_uri: self.class.redirect_uri, grant_type: "authorization_code"
      })
    end

    def refresh
      @http.request(:post, "https://oauth2.googleapis.com/token", form: {
        refresh_token: @connection.refresh_token, client_id: @connection.client_id,
        client_secret: @connection.client_secret, grant_type: "refresh_token"
      })
    end
  end
end
