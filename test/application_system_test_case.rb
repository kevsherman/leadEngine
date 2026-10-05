require "test_helper"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1440, 1000 ] do |options|
    options.add_argument("--disable-dev-shm-usage")
    options.add_argument("--no-sandbox") if ENV["CI"]
  end
end
