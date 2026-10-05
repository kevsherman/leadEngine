require "test_helper"
require_relative "../support/gmail_fixture_client"

class GmailConnectionTest < ActionDispatch::IntegrationTest
  include GmailFixtures
  setup do
    create_gmail_connection
    @operator = Operator.create!(email: "operator@example.test", password: "test-password")
  end

  def sign_in
    post session_path, params: { email: @operator.email, password: "test-password" }
  end

  test "connection setup and OAuth actions require operator login" do
    get gmail_connection_path
    assert_redirected_to new_session_path
    post connect_gmail_connection_path
    assert_redirected_to new_session_path
    get gmail_callback_path, params: { state: "attacker", code: "secret-code" }
    assert_redirected_to new_session_path
  end

  test "OAuth uses only requested scopes with offline consent PKCE and fixed callback" do
    sign_in
    post connect_gmail_connection_path
    assert_response :redirect
    url = URI(response.location)
    values = URI.decode_www_form(url.query).to_h
    assert_equal "accounts.google.com", url.host
    assert_equal GmailConnection::SCOPES, values["scope"].split
    assert_equal "offline", values["access_type"]
    assert_equal "consent", values["prompt"]
    assert_equal "S256", values["code_challenge_method"]
    assert_equal "http://127.0.0.1:3000/gmail/callback", values["redirect_uri"]
    assert_equal GmailConnection::MAILBOX, values["login_hint"]
    assert values["state"].present?
  end

  test "forged and reused OAuth state cannot connect" do
    sign_in
    before = @connection.authorization_version
    get gmail_callback_path, params: { state: "attacker", code: "code" }
    assert_redirected_to gmail_connection_path
    assert_equal before, @connection.reload.authorization_version
    post connect_gmail_connection_path
    state = URI.decode_www_form(URI(response.location).query).to_h.fetch("state")
    get gmail_callback_path, params: { state: "wrong", code: "code" }
    get gmail_callback_path, params: { state: state, code: "code" }
    assert_equal before, @connection.reload.authorization_version
  end

  test "wrong mailbox is rejected and correct callback enables reading with sending off" do
    sign_in
    oauth = Object.new
    oauth.define_singleton_method(:exchange) do |**_|
      { "scope" => GmailConnection::SCOPES.join(" "), "access_token" => "new-access", "refresh_token" => "new-refresh", "expires_in" => 3600 }
    end
    client = GmailFixtures::Client.new
    client.profile_result = { "emailAddress" => "wrong@example.test", "historyId" => "1" }
    post connect_gmail_connection_path
    state = URI.decode_www_form(URI(response.location).query).to_h.fetch("state")
    Gmail::Oauth.stub(:new, oauth) do
      Gmail::Client.stub(:new, client) { get gmail_callback_path, params: { state: state, code: "synthetic-code" } }
    end
    assert_equal "needs_authorization", @connection.reload.status
    assert_equal "wrong_google_account_select_kevin", @connection.last_error
    post connect_gmail_connection_path
    state = URI.decode_www_form(URI(response.location).query).to_h.fetch("state")
    client.profile_result = { "emailAddress" => GmailConnection::MAILBOX, "historyId" => "1" }
    Gmail::Oauth.stub(:new, oauth) do
      Gmail::Client.stub(:new, client) { get gmail_callback_path, params: { state: state, code: "synthetic-code" } }
    end
    assert_equal "connected", @connection.reload.status
    assert @connection.polling_enabled?
    assert_not @connection.sending_enabled?
    assert_equal "new-refresh", @connection.refresh_token
  end

  test "secrets are encrypted in SQL filtered from parameters and absent from HTML" do
    sign_in
    get gmail_connection_path
    assert_response :success
    assert_not_includes response.body, "synthetic-secret"
    assert_not_includes response.body, "synthetic-refresh"
    stored = GmailConnection.connection.select_value("SELECT client_secret FROM gmail_connections WHERE id = #{@connection.id}")
    assert_not_equal "synthetic-secret", stored
    assert_includes stored, '"p"'
    filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
    values = filter.filter({ code: "private-code", client_secret: "private-secret", refresh_token: "private-refresh", raw: "private-email" })
    assert values.values.all? { |value| value == "[FILTERED]" }
  end

  test "changing OAuth credentials stops polling and invalidates previous send authority" do
    sign_in
    patch gmail_connection_path, params: { gmail_connection: { client_secret: "rotated-secret" } }
    assert_redirected_to gmail_connection_path
    assert_not @connection.reload.polling_enabled?
    assert_not @connection.sending_enabled?
    assert_nil @connection.refresh_token
    assert_equal 1, @connection.authorization_version
  end

  test "enabling sending requires manual confirmation and accepted alias" do
    sign_in
    post enable_sending_gmail_connection_path
    assert_redirected_to gmail_connection_path
    @connection.update!(sending_enabled: false)
    client = GmailFixtures::Client.new
    client.alias_result["verificationStatus"] = "pending"
    Gmail::Client.stub(:new, client) { post enable_sending_gmail_connection_path, params: { alias_confirmed: "1" } }
    assert_not @connection.reload.sending_enabled?
    client.alias_result["verificationStatus"] = "accepted"
    Gmail::Client.stub(:new, client) { post enable_sending_gmail_connection_path, params: { alias_confirmed: "1" } }
    assert @connection.reload.sending_enabled?
    post disconnect_gmail_connection_path
    assert_equal "disabled", @connection.reload.status
    assert_nil @connection.refresh_token
  end
end
