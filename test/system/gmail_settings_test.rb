require "application_system_test_case"
require_relative "../support/gmail_fixture_client"

class GmailSettingsTest < ApplicationSystemTestCase
  include GmailFixtures
  setup { create_inquiry }

  test "operator can configure Gmail without displaying secrets or enabling sending" do
    visit root_path
    fill_in "Operator email", with: @operator.email
    fill_in "Password", with: "test-password"
    click_button "Sign in"
    click_link "Gmail connection"
    assert_text "Gmail for the inquiry desk"
    assert_text "Live sending: Off"
    fill_in "Google OAuth client ID", with: "synthetic-client.apps.googleusercontent.com"
    fill_in "Client secret (blank keeps the saved secret)", with: "synthetic-browser-secret"
    click_button "Save Gmail configuration"
    assert_text "Gmail settings saved."
    assert_equal "", find("input[type=password]").value
    assert_no_text "synthetic-browser-secret"
    assert_no_button "Verify alias and enable reviewed sending"
    page.save_screenshot(Rails.root.join("tmp/screenshots/gmail-settings-desktop.png"))
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 390, height: 844, deviceScaleFactor: 1, mobile: true)
    assert page.evaluate_script("document.documentElement.scrollWidth <= window.innerWidth"), "Gmail settings must fit mobile"
    page.save_screenshot(Rails.root.join("tmp/screenshots/gmail-settings-mobile.png"))
  end

  test "a Gmail draft clearly requires separate real email confirmation" do
    create_gmail_connection
    client = GmailFixtures::Client.new("m1" => gmail_message)
    Gmail::Importer.new(@connection, client: client).import_id("m1")
    conversation = Conversation.find_by(email_provider: "gmail")
    visit root_path
    fill_in "Operator email", with: @operator.email
    fill_in "Password", with: "test-password"
    click_button "Sign in"
    visit conversation_path(conversation)
    assert_text "Gmail conversation"
    fill_in "Reply", with: "Please confirm your address."
    click_button "Save draft"
    click_link "Review saved reply"
    assert_text "Gmail · live after explicit send confirmation"
    click_button "Approve this saved reply"
    assert_unchecked_field "confirm_live"
    assert_button "Send approved reply through Gmail"
    assert_equal 0, SendOperation.where(provider: "gmail").count
    # Browser validation prevents sending without the required confirmation.
    click_button "Send approved reply through Gmail"
    assert_equal 0, SendOperation.where(provider: "gmail").count
    page.save_screenshot(Rails.root.join("tmp/screenshots/gmail-live-review.png"))
    draft = conversation.email_draft.reload
    operation = ReplyWorkflow.enqueue(draft, @operator, draft.lock_version, confirm_live: true)
    operation.update!(status: "sending")
    visit conversation_path(conversation)
    assert_button "Check Gmail send status"
    assert_no_button "Retry approved Gmail send"
  end
end
