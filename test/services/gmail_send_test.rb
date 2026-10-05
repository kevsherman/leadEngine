require "test_helper"
require_relative "../support/gmail_fixture_client"

class GmailSendTest < ActiveSupport::TestCase
  include GmailFixtures
  include ActiveJob::TestHelper
  setup do
    create_gmail_connection
    @client = GmailFixtures::Client.new("m1" => gmail_message)
    Gmail::Importer.new(@connection, client: @client).import_id("m1")
    @conversation = Conversation.first
    @draft = @conversation.email_draft
    @draft.update!(body: "Please confirm your full delivery address.")
    @operator = Operator.create!(email: "operator@example.test", password: "test-password")
    ReplyWorkflow.approve(@draft, @operator, @draft.lock_version)
  end

  def request_send
    ReplyWorkflow.enqueue(@draft, @operator, @draft.lock_version, confirm_live: true)
  end

  def run_send(operation)
    Gmail::Client.stub(:new, @client) { GmailSendJob.perform_now(operation.id) }
  end

  test "live confirmation and accepted sales alias are required" do
    assert_raises(ReplyWorkflow::InvalidTransition) { ReplyWorkflow.enqueue(@draft, @operator, @draft.lock_version) }
    @connection.update!(sending_enabled: false)
    assert_raises(ReplyWorkflow::InvalidTransition) { request_send }
    assert_equal 0, SendOperation.count
    assert_equal 0, @client.sent_count
  end

  test "approved mail uses sales identity RFC threading and a stable message id" do
    operation = request_send
    run_send(operation)
    run_send(operation)
    assert_equal 1, @client.sent_count
    assert_equal "sent", operation.reload.status
    raw = Base64.urlsafe_decode64(@client.calls.find { |call| call[0] == :send }[1])
    email = Mail.read_from_string(raw)
    assert_equal [ GmailConnection::SALES_ADDRESS ], email.from
    assert_equal [ GmailConnection::SALES_ADDRESS ], email.reply_to
    assert_equal [ "morgan@example.test" ], email.to
    assert_equal "m1@example.test", email.in_reply_to
    assert_includes Array(email.references), "m1@example.test"
    assert_equal operation.rfc_message_id.delete_prefix("<").delete_suffix(">"), email.message_id
    assert_equal "thread1", @client.calls.find { |call| call[0] == :send }[2]
    assert_equal "sent1", operation.provider_message_id
    assert_equal 1, @conversation.messages.where(direction: "outbound").count
    assert_equal 0, FakeDelivery.count
  end

  test "a definite rejected send stays recoverable with the same operation" do
    operation = request_send
    @client.send_error = Gmail::Error.new("gmail_http_403")
    run_send(operation)
    assert_equal "failed", operation.reload.status
    assert_equal 0, @conversation.messages.where(direction: "outbound").count
    @client.send_error = nil
    assert_equal operation.id, request_send.id
    run_send(operation)
    assert_equal "sent", operation.reload.status
    assert_equal 1, @conversation.messages.where(direction: "outbound").count
  end

  test "timeout reconciles Sent mail instead of resending and poll import deduplicates" do
    operation = request_send
    @client.send_error = Gmail::UncertainWrite.new("gmail_send_outcome_unknown")
    run_send(operation)
    assert_equal "unknown", operation.reload.status
    assert_raises(ReplyWorkflow::InvalidTransition) { request_send }
    run_send(operation)
    assert_equal 1, @client.sent_count
    sent = gmail_message(id: "sent1", from: GmailConnection::SALES_ADDRESS, to: "morgan@example.test", labels: [ "SENT" ])
    sent["payload"]["headers"].find { |header| header["name"] == "Message-ID" }["value"] = operation.rfc_message_id
    @client.messages = { "sent1" => sent }
    Gmail::Client.stub(:new, @client) { GmailReconcileJob.perform_now(operation.id) }
    assert_equal "sent", operation.reload.status
    Gmail::Importer.new(@connection, client: @client).import_id("sent1")
    assert_equal 1, @conversation.messages.where(direction: "outbound").count
    assert_equal 1, @client.sent_count
  end

  test "a worker crash after claiming a send reconciles without posting again" do
    operation = request_send
    operation.update!(status: "sending")
    assert_enqueued_with(job: GmailReconcileJob, args: [ operation.id ]) { run_send(operation) }
    assert_equal 0, @client.sent_count
    @client.messages = {}
    Gmail::Client.stub(:new, @client) { GmailReconcileJob.perform_now(operation.id) }
    assert_equal "unknown", operation.reload.status
    assert_equal "unknown", @draft.reload.status
    assert_raises(ReplyWorkflow::InvalidTransition) { request_send }
  end

  test "empty reconciliation does not permit another send" do
    operation = request_send
    @client.send_error = Gmail::UncertainWrite.new
    run_send(operation)
    @client.messages = {}
    Gmail::Client.stub(:new, @client) { GmailReconcileJob.perform_now(operation.id) }
    assert_equal "unknown", operation.reload.status
    assert_raises(ReplyWorkflow::InvalidTransition) { request_send }
    assert_equal 1, @client.sent_count
  end

  test "new customer message or changed authorization blocks a queued send" do
    operation = request_send
    @connection.update!(authorization_version: 1)
    run_send(operation)
    assert_equal "blocked", operation.reload.status
    assert_equal 0, @client.sent_count
  end

  test "pending send is invalidated by a newly imported customer message" do
    operation = request_send
    @client.messages["m2"] = gmail_message(id: "m2", to: GmailConnection::MAILBOX, timestamp: 1.minute.from_now)
    Gmail::Importer.new(@connection, client: @client).import_id("m2")
    run_send(operation)
    assert_equal "blocked", operation.reload.status
    assert_equal 0, @client.sent_count
  end

  test "a customer reply after delivery opens a fresh draft without overwriting sent history" do
    operation = request_send
    run_send(operation)
    @client.messages["m2"] = gmail_message(id: "m2", to: GmailConnection::MAILBOX, timestamp: 2.minutes.from_now)
    Gmail::Importer.new(@connection, client: @client).import_id("m2")
    assert_equal 2, @conversation.email_drafts.count
    assert_equal "sent", @draft.reload.status
    assert_equal "editing", @conversation.email_draft.status
    assert_equal "needs_review", @conversation.reload.status
    assert_equal "sent1", operation.reload.provider_message_id
  end
end
