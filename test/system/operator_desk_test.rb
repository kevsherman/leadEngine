require "application_system_test_case"

class OperatorDeskTest < ApplicationSystemTestCase
  setup { create_inquiry }

  test "operator edits reviews approves and sees a simulated reply" do
    visit root_path
    fill_in "Operator email", with: @operator.email
    fill_in "Password", with: "test-password"
    click_button "Sign in"
    assert_text "Every inquiry, in one place."
    click_link "Morgan"
    assert_selector "h1", text: "Courtyard"
    fill_in "Reply", with: "Please share your full delivery address."
    assert_text "Unsaved changes."
    click_button "Save draft"
    assert_text "Draft saved."
    click_link "Review saved reply"
    assert_text "Please share your full delivery address."
    assert_text "Attachments"
    click_button "Approve this saved reply"
    assert_text "Exact saved reply approved."
    click_button "Simulate sending approved reply"
    assert_text "Simulated reply queued"
    SendReplyJob.perform_now(@draft.reload.send_operation.id)
    assert_text "Simulated email", wait: 10
    assert_text "Waiting for customer"
    assert_selector ".message.outbound", count: 1
    page.save_screenshot(Rails.root.join("tmp/screenshots/operator-desktop.png"))
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 390, height: 844, deviceScaleFactor: 1, mobile: true)
    assert_equal 390, page.evaluate_script("window.innerWidth")
    assert_text "Reply draft"
    assert page.evaluate_script("document.documentElement.scrollWidth <= window.innerWidth"), "Mobile screen must not overflow horizontally"
    page.save_screenshot(Rails.root.join("tmp/screenshots/operator-mobile.png"))
    click_button "Sign out"
    assert_selector "input[type=password]"
  end
end
