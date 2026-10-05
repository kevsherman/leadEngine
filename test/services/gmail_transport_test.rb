require "test_helper"
require_relative "../support/gmail_fixture_client"

class GmailTransportTest < ActiveSupport::TestCase
  include GmailFixtures
  setup { create_gmail_connection }

  class Transport
    attr_accessor :use_ssl, :open_timeout, :read_timeout, :write_timeout, :max_retries, :response, :error
    attr_reader :requests
    def initialize(status: "200", body: "{}")
      @response = Struct.new(:code, :body).new(status, body)
      @requests = []
    end
    def request(request)
      @requests << request
      raise @error if @error
      @response
    end
  end

  test "HTTP transport sets bearer authorization bounded timeouts and disables write retries" do
    transport = Transport.new(body: '{"id":"sent1"}')
    result = Net::HTTP.stub(:new, transport) do
      Gmail::Http.new.request(:post, "https://gmail.googleapis.com/gmail/v1/users/me/messages/send", token: "synthetic", json: { raw: "encoded" }, write: true)
    end
    assert_equal "sent1", result["id"]
    assert_equal "Bearer synthetic", transport.requests.first["Authorization"]
    assert_equal 0, transport.max_retries
    assert_equal 25, transport.read_timeout
    assert transport.use_ssl
  end

  test "send timeout and 5xx are uncertain but 403 is a definite failure" do
    transport = Transport.new(status: "503", body: "private-response-body")
    error = Net::HTTP.stub(:new, transport) do
      assert_raises(Gmail::UncertainWrite) { Gmail::Http.new.request(:post, "https://gmail.googleapis.com/test", write: true) }
    end
    assert_equal "gmail_send_outcome_unknown", error.message
    assert_not_includes error.message, "private-response"
    transport.response.code = "403"
    Net::HTTP.stub(:new, transport) do
      error = assert_raises(Gmail::Error) { Gmail::Http.new.request(:post, "https://gmail.googleapis.com/test", write: true) }
      assert_not error.is_a?(Gmail::UncertainWrite)
    end
    transport.error = Net::ReadTimeout.new("secret-response")
    Net::HTTP.stub(:new, transport) do
      error = assert_raises(Gmail::UncertainWrite) { Gmail::Http.new.request(:post, "https://gmail.googleapis.com/test", write: true) }
      assert_nil error.cause
    end
  end

  test "token refresh uses encrypted refresh token and preserves offline grant" do
    @connection.update!(expires_at: 1.minute.ago)
    transport = Object.new
    calls = []
    transport.define_singleton_method(:request) do |method, url, **args|
      calls << [ method, url, args ]
      { "access_token" => "refreshed-access", "expires_in" => 3600 }
    end
    client = Gmail::Client.new(@connection, http: transport)
    assert_equal "refreshed-access", client.token
    assert_equal "synthetic-refresh", calls.first[2][:form][:refresh_token]
    assert_equal "refresh_token", calls.first[2][:form][:grant_type]
    assert_equal "synthetic-refresh", @connection.reload.refresh_token
    assert @connection.expires_at > 50.minutes.from_now
  end

  test "multipart HTML forms and attachment metadata never require fetching attachments" do
    html = "<div>Name: Morgan</div><div>Email: morgan@example.test</div><div>Body: Please quote 80 blocks.</div>"
    payload = { "mimeType" => "multipart/mixed", "parts" => [
      { "mimeType" => "text/html", "body" => { "data" => Base64.urlsafe_encode64(html) } },
      { "mimeType" => "application/pdf", "filename" => "plans.pdf", "body" => { "attachmentId" => "attachment1", "size" => 2000 } }
    ] }
    body = Gmail::Content.read(payload)
    assert_includes body, "Name: Morgan\n"
    assert_equal "plans.pdf", Gmail::Content.attachments(payload).first[:filename]
    envelope = Gmail::Envelope.new(gmail_message)
    assert_equal "morgan@example.test", Gmail::ShopifyForm.parse(body, envelope)[:email]
  end
end
