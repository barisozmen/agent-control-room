require "test_helper"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :rack_test

  Capybara.default_max_wait_time = 5
  Capybara.default_normalize_ws = true
end
