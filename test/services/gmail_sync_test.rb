require "test_helper"
require_relative "../support/gmail_fixture_client"

class GmailSyncTest < ActiveSupport::TestCase
  include GmailFixtures
  setup { create_gmail_connection }

  test "bootstrap imports sales and excludes unrelated bodies with repeat-safe checkpoints" do
    sales = gmail_message
    private_mail = gmail_message(id: "personal", thread: "private", from: "friend@example.test", to: GmailConnection::MAILBOX, body: "Private unrelated content.")
    client = GmailFixtures::Client.new("m1" => sales, "personal" => private_mail)
    Gmail::Synchronizer.new(@connection, client: client).call(force: true)
    assert_equal 1, Conversation.count
    assert_equal 1, Message.count
    assert_equal "100", @connection.reload.history_id
    assert_not_includes client.calls, [ :message, "personal", "full" ]
    assert_equal "morgan@example.test", Conversation.first.customer_email
    Gmail::Synchronizer.new(@connection, client: client).call(force: true)
    assert_equal 1, Message.count
    assert_equal "200", @connection.reload.history_id
    assert_equal "editing", EmailDraft.first.status
  end

  test "Shopify notification extracts actual customer and flags mismatched reply address" do
    form = gmail_message(from: "mailer@shopify.com", to: GmailConnection::MAILBOX, subject: "New customer message on October 4",
      reply_to: "morgan@example.test", body: "Country Code: CA\nName: Morgan Chen\nEmail: morgan@example.test\nPhone Number: 555-0100\nBody:\nI need 80 Clover blocks.\nCan you quote delivery?")
    client = GmailFixtures::Client.new("m1" => form)
    importer = Gmail::Importer.new(@connection, client: client)
    importer.import_id("m1")
    importer.import_id("m1")
    assert_equal 1, Conversation.count
    assert_equal "morgan@example.test", Conversation.first.customer_email
    assert_equal "Morgan Chen", Conversation.first.customer_name
    assert_equal "morgan@example.test", EmailDraft.first.to
    assert_equal "mailer@shopify.com", Message.first.sender
    assert_includes Message.first.body, "Can you quote delivery?"
    client.messages["m2"] = gmail_message(id: "m2", thread: "form2", from: "mailer@shopify.com", to: GmailConnection::MAILBOX,
      subject: "New customer message", reply_to: "other@example.test", body: "Name: Morgan\nEmail: morgan@example.test\nBody: Please quote.")
    importer.import_id("m2")
    assert_equal 1, Conversation.count
    assert_equal "shopify_customer_identity_uncertain", GmailReviewItem.first.reason
    assert_not GmailReviewItem.column_names.include?("body")
  end

  test "customer reply addressed to Kevin and Gmail-sent reply remain in one conversation" do
    client = GmailFixtures::Client.new("m1" => gmail_message)
    importer = Gmail::Importer.new(@connection, client: client)
    importer.import_id("m1")
    conversation = Conversation.first
    operator = Operator.create!(email: "operator@example.test", password: "test-password")
    conversation.email_draft.update!(body: "Please confirm your address.")
    ReplyWorkflow.approve(conversation.email_draft, operator, conversation.email_draft.lock_version)
    client.messages["m2"] = gmail_message(id: "m2", to: GmailConnection::MAILBOX, body: "Our full address is ...")
    client.messages["m3"] = gmail_message(id: "m3", from: GmailConnection::MAILBOX, to: "morgan@example.test", body: "Thanks, I will review.", labels: [ "SENT" ])
    importer.import_id("m2")
    assert_equal "editing", conversation.email_draft.reload.status
    importer.import_id("m3")
    importer.import_id("m3")
    assert_equal 1, Conversation.count
    assert_equal 3, conversation.messages.count
    assert_equal 1, conversation.messages.where(direction: "outbound").count
    assert_equal "waiting_for_customer", conversation.reload.status
  end

  test "references join a new Gmail thread while unrelated mail from same customer stays excluded" do
    client = GmailFixtures::Client.new("m1" => gmail_message)
    importer = Gmail::Importer.new(@connection, client: client)
    importer.import_id("m1")
    client.messages["m2"] = gmail_message(id: "m2", thread: "new-thread", to: GmailConnection::MAILBOX, reference: "<m1@example.test>")
    client.messages["unrelated"] = gmail_message(id: "unrelated", thread: "private-thread", to: GmailConnection::MAILBOX, subject: "Dinner plans")
    importer.import_id("m2")
    importer.import_id("unrelated")
    assert_equal 1, Conversation.count
    assert_equal 2, Message.count
    assert_not_includes client.calls, [ :message, "unrelated", "full" ]
  end

  test "spam draft and an unrelated participant in a tracked thread are not imported" do
    client = GmailFixtures::Client.new("m1" => gmail_message)
    importer = Gmail::Importer.new(@connection, client: client)
    importer.import_id("m1")
    client.messages["spam"] = gmail_message(id: "spam", labels: [ "SPAM" ])
    client.messages["draft"] = gmail_message(id: "draft", labels: [ "DRAFT" ])
    client.messages["other"] = gmail_message(id: "other", from: "stranger@example.test", to: GmailConnection::MAILBOX)
    %w[spam draft other].each { |id| importer.import_id(id) }
    assert_equal 1, Message.count
    assert_not_includes client.calls, [ :message, "other", "full" ]
    assert_equal 1, GmailReviewItem.count
  end

  test "paginated history advances only after imports and failure leaves cursor recoverable" do
    @connection.update!(history_id: "100")
    client = GmailFixtures::Client.new("m1" => gmail_message, "m2" => gmail_message(id: "m2"))
    client.history_pages = {
      nil => { "historyId" => "200", "nextPageToken" => "next", "history" => [ { "messagesAdded" => [ { "message" => { "id" => "m1" } } ] } ] },
      "next" => { "historyId" => "200", "history" => [ { "messagesAdded" => [ { "message" => { "id" => "m2" } } ] } ] }
    }
    Gmail::Synchronizer.new(@connection, client: client).call(force: true)
    assert_equal 2, Message.count
    assert_equal "200", @connection.reload.history_id
    client.history_error = Gmail::AuthorizationError.new("google_authorization_required")
    Gmail::Synchronizer.new(@connection, client: client).call(force: true)
    assert_equal "200", @connection.reload.history_id
    assert_equal "needs_authorization", @connection.status
    assert_equal "google_authorization_required", @connection.last_error
  end

  test "expired cursor recovers through filtered full sync without duplicate imports" do
    @connection.update!(history_id: "expired")
    client = GmailFixtures::Client.new("m1" => gmail_message)
    client.history_error = Gmail::NotFound.new
    Gmail::Synchronizer.new(@connection, client: client).call(force: true)
    assert_equal 1, Message.count
    assert_equal "100", @connection.reload.history_id
    assert client.calls.any? { |call| call[0] == :list && call[1].include?("to:sales@breezeblock.ca") }
  end

  test "body retrieval failure does not advance the history cursor" do
    @connection.update!(history_id: "100")
    client = GmailFixtures::Client.new("m1" => gmail_message)
    client.history_pages = { nil => { "historyId" => "200", "history" => [ { "messagesAdded" => [ { "message" => { "id" => "m1" } } ] } ] } }
    original = client.method(:message)
    client.define_singleton_method(:message) do |id, format: "metadata"|
      raise Gmail::Error.new("gmail_http_503") if format == "full"
      original.call(id, format: format)
    end
    Gmail::Synchronizer.new(@connection, client: client).call(force: true)
    assert_equal "100", @connection.reload.history_id
    assert_equal "error", @connection.status
    assert_equal 0, Message.count
  end

  test "poll overlap is excluded by a PostgreSQL advisory lock" do
    client = GmailFixtures::Client.new("m1" => gmail_message)
    lock_key = 7_241_100 + @connection.id
    # A separate DB session holds the lock, as another worker would.
    separate = PG.connect(host: ENV.fetch("PGHOST", "127.0.0.1"), port: ENV.fetch("PGPORT", "55432"),
      user: ENV.fetch("PGUSER", ENV.fetch("USER")), password: ENV["PGPASSWORD"], dbname: "inquiry_to_quote_test")
    separate.exec("SELECT pg_advisory_lock(#{lock_key})")
    Gmail::Synchronizer.new(@connection, client: client).call(force: true)
    assert_equal 0, Message.count
    assert_empty client.calls
  ensure
    separate&.close
  end

  test "unknown Shopify formats are reviewed without treating the mailer as a customer" do
    mail = gmail_message(from: "mailer@shopify.com", subject: "Store notification", body: "Unrecognized form layout")
    client = GmailFixtures::Client.new("m1" => mail)
    Gmail::Importer.new(@connection, client: client).import_id("m1")
    assert_equal 0, Conversation.count
    assert_equal "unrecognized_shopify_notification", GmailReviewItem.first.reason
    assert_not_includes client.calls, [ :message, "m1", "full" ]
  end

  test "an explicitly reviewed message is imported once with the operator confirmed identity" do
    mail = gmail_message(from: "mailer@shopify.com", subject: "New customer message", body: "Unusual notification layout")
    client = GmailFixtures::Client.new("m1" => mail)
    importer = Gmail::Importer.new(@connection, client: client)
    importer.import_id("m1")
    item = GmailReviewItem.first
    2.times { importer.import_review(item, email: "confirmed@example.test", name: "Confirmed Customer") }
    assert_equal 1, Conversation.count
    assert_equal 1, Message.count
    assert_equal "confirmed@example.test", EmailDraft.first.to
    assert item.reload.resolved?
  end
end
