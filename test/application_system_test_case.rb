# Browser tests need live updates to really reach the browser, so use the in-process cable
# adapter (the normal tests use the recording "test" adapter). Must be set before Rails loads.
ENV["CABLE_ADAPTER"] = "async"

require "test_helper"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1500, 1000 ]

  def sign_in_through_browser(user)
    visit new_session_path
    fill_in "Email", with: user.email_address
    fill_in "Password", with: "password"
    click_button "Sign in"
    assert_text "Welcome, #{user.first_name}"
  end
end
