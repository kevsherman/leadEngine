require "test_helper"

class ReplyWorkflowTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  setup { create_inquiry }

  test "unapproved sending is blocked" do
    assert_raises(ReplyWorkflow::InvalidTransition) { ReplyWorkflow.enqueue(@draft, @operator, @draft.lock_version) }
    assert_equal 0, SendOperation.count
    assert_equal 0, FakeDelivery.count
  end

  test "editing invalidates approval and stale review cannot approve" do
    version = @draft.lock_version
    ReplyWorkflow.approve(@draft, @operator, version)
    @draft.update!(body: "A revised question.")
    assert_equal "editing", @draft.status
    assert_nil @draft.approved_at
    assert_raises(ReplyWorkflow::InvalidTransition) { ReplyWorkflow.approve(@draft, @operator, version) }
  end

  test "a customer reply invalidates the previous approval" do
    ReplyWorkflow.approve(@draft, @operator, @draft.lock_version)
    @conversation.messages.create!(provider_id: "new-inbound", direction: "inbound", sender: "morgan@example.test", subject: "Re: Courtyard", body: "Actually, make that 90.")
    assert_raises(ReplyWorkflow::InvalidTransition) { ReplyWorkflow.enqueue(@draft, @operator, @draft.lock_version) }
    assert_equal 0, SendOperation.count
  end

  test "duplicate send submissions and job execution produce one exact local delivery" do
    ReplyWorkflow.approve(@draft, @operator, @draft.lock_version)
    approved_version = @draft.lock_version
    assert_enqueued_jobs 1 do
      @operation = ReplyWorkflow.enqueue(@draft, @operator, approved_version)
    end
    repeat = ReplyWorkflow.enqueue(@draft, @operator, approved_version)
    assert_equal @operation.id, repeat.id
    assert_raises(ActiveRecord::RecordNotSaved) { @draft.update!(body: "Changed after sending.") }
    2.times { SendReplyJob.perform_now(@operation.id) }
    assert_equal 1, FakeDelivery.count
    assert_equal 1, @conversation.messages.where(direction: "outbound").count
    payload = FakeDelivery.first.payload
    assert_equal "Please confirm your delivery address.", payload["body"]
    assert_equal "sales@breezeblock.ca", payload["from"]
    assert_equal "test-message", payload["in_reply_to"]
    assert_equal "waiting_for_customer", @conversation.reload.status
    assert_equal "sent", @draft.reload.status
    assert_equal %w[draft_approved fake_send_requested fake_email_delivered], @conversation.audit_events.order(:id).pluck(:action)
  end

  test "a failed fake delivery can be retried without duplicate effects" do
    ReplyWorkflow.approve(@draft, @operator, @draft.lock_version)
    operation = ReplyWorkflow.enqueue(@draft, @operator, @draft.lock_version)
    provider = Providers::FakeEmail.new
    provider.define_singleton_method(:deliver) { |_| raise IOError, "Synthetic failure" }
    Providers::FakeEmail.stub(:new, provider) do
      assert_raises(IOError) { SendReplyJob.perform_now(operation.id) }
    end
    assert_equal "failed", operation.reload.status
    assert_equal 0, FakeDelivery.count
    SendReplyJob.perform_now(operation.id)
    assert_equal "sent", operation.reload.status
    assert_equal 1, FakeDelivery.count
  end

  test "queue outage preserves one approved operation for retry" do
    ReplyWorkflow.approve(@draft, @operator, @draft.lock_version)
    version = @draft.lock_version
    failing_enqueue = ->(*) { raise ActiveJob::EnqueueError, "Synthetic queue outage" }
    SendReplyJob.stub(:perform_later, failing_enqueue) do
      assert_raises(ReplyWorkflow::InvalidTransition) { ReplyWorkflow.enqueue(@draft, @operator, version) }
    end
    assert_equal 1, SendOperation.count
    assert_equal "queued", @draft.reload.status
    operation = ReplyWorkflow.enqueue(@draft, @operator, version)
    SendReplyJob.perform_now(operation.id)
    assert_equal 1, FakeDelivery.count
  end
end
