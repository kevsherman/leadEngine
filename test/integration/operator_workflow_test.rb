require "test_helper"

class OperatorWorkflowTest < ActionDispatch::IntegrationTest
  setup { create_inquiry }

  test "private screens and write actions require login" do
    get root_path
    assert_redirected_to new_session_path
    get review_email_draft_path(@draft)
    assert_redirected_to new_session_path
    post approve_email_draft_path(@draft), params: { lock_version: @draft.lock_version }
    assert_redirected_to new_session_path
    post send_reply_email_draft_path(@draft), params: { lock_version: @draft.lock_version }
    assert_redirected_to new_session_path
    assert_equal "editing", @draft.reload.status
  end

  test "login queue search save review approve and send" do
    post session_path, params: { email: @operator.email, password: "wrong" }
    assert_response :unprocessable_entity
    post session_path, params: { email: @operator.email, password: "test-password" }
    assert_redirected_to root_path
    get conversations_path, params: { search: "Vancouver", status: "needs_review" }
    assert_select "nav a", count: 1
    get conversations_path, params: { search: "No matching project" }
    assert_select "nav a", count: 0
    get conversation_path(@conversation)
    assert_response :success
    patch email_draft_path(@draft), params: { email_draft: { body: "What is the full address?", lock_version: @draft.lock_version } }
    assert_redirected_to conversation_path(@conversation)
    get review_email_draft_path(@draft)
    assert_select ".review-body", text: /What is the full address/
    post approve_email_draft_path(@draft), params: { lock_version: @draft.reload.lock_version }
    assert_equal "approved", @draft.reload.status
    post send_reply_email_draft_path(@draft), params: { lock_version: @draft.lock_version }
    assert_equal "queued", @draft.reload.status
    delete session_path
    get root_path
    assert_redirected_to new_session_path
  end

  test "malicious customer HTML is escaped" do
    post session_path, params: { email: @operator.email, password: "test-password" }
    @conversation.messages.first.update!(body: '<script>alert("customer")</script>')
    get conversation_path(@conversation)
    assert_select "article script", count: 0
  end
end
