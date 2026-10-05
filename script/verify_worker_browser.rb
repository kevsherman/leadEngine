# Run with: source script/env && bundle exec ruby script/verify_worker_browser.rb
# Requires bin/dev. Exercises one seeded conversation using the real worker.
require "selenium-webdriver"
require "fileutils"

options = Selenium::WebDriver::Chrome::Options.new
options.add_argument("--headless=new")
options.add_argument("--window-size=1440,1100")
driver = Selenium::WebDriver.for(:chrome, options: options)
wait = Selenium::WebDriver::Wait.new(timeout: 20)

def text_on_page(driver, text)
  driver.find_element(tag_name: "body").text.include?(text)
end

begin
  driver.navigate.to("http://127.0.0.1:3000")
  driver.find_element(name: "email").send_keys(ENV.fetch("OPERATOR_EMAIL", "kevin@example.test"))
  driver.find_element(name: "password").send_keys(ENV.fetch("OPERATOR_PASSWORD", "local-demo-password"))
  driver.find_element(css: "input[type=submit]").click
  wait.until { text_on_page(driver, "Every inquiry, in one place.") }
  driver.find_element(partial_link_text: "Morgan Chen").click
  wait.until { text_on_page(driver, "Reply draft") }
  unless text_on_page(driver, "Reply status: Sent")
    body = driver.find_element(id: "email_draft_body")
    body.clear
    body.send_keys("Hi Morgan,\n\nCould you confirm the full delivery address, site type, unloading equipment and access restrictions for the courtyard project? We will confirm pricing and availability when preparing a quote.\n\nBest,\nKevin\nBreeze Block Canada")
    driver.find_element(css: "input[value='Save draft']").click
    wait.until { text_on_page(driver, "Draft saved.") }
    driver.find_element(link_text: "Review saved reply").click
    wait.until { text_on_page(driver, "The exact saved reply") }
    driver.find_element(css: "button.btn.primary").click
    wait.until { text_on_page(driver, "Exact saved reply approved.") }
    driver.find_element(css: ".approved-box button").click
  end
  wait.until { text_on_page(driver, "Reply status: Sent") }
  raise "Missing worker delivery" unless driver.find_elements(css: ".message.outbound").size == 1
  raise "Missing next state" unless text_on_page(driver, "Waiting for customer")
  FileUtils.mkdir_p("tmp/screenshots")
  driver.execute_script("window.scrollTo(0,0)")
  driver.save_screenshot("tmp/screenshots/worker-desktop.png")
  driver.execute_cdp("Emulation.setDeviceMetricsOverride", width: 390, height: 844, deviceScaleFactor: 1, mobile: true)
  raise "Wrong mobile viewport" unless driver.execute_script("return window.innerWidth") == 390
  raise "Mobile overflow" unless driver.execute_script("return document.documentElement.scrollWidth <= window.innerWidth")
  driver.save_screenshot("tmp/screenshots/worker-mobile.png")
  puts "PASS: Chrome login → edit → approve → dedicated worker → one fake receipt, with desktop and 390px mobile screenshots."
ensure
  driver.quit
end
