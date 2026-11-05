require "test_helper"

class PasswordsControllerTest < ActionDispatch::IntegrationTest
  setup { @user = agent }

  test "new" do
    get new_password_path
    assert_response :success
  end

  test "create sends a reset email for a real address, and says the same for an unknown one" do
    assert_enqueued_emails 1 do
      post passwords_path, params: { email_address: @user.email_address }
    end
    assert_redirected_to new_session_path

    assert_enqueued_emails 0 do
      post passwords_path, params: { email_address: "missing-user@example.com" }
    end
    assert_redirected_to new_session_path
  end

  test "edit with a valid token, and a bad token" do
    get edit_password_path(@user.password_reset_token)
    assert_response :success
    get edit_password_path("invalid token")
    assert_redirected_to new_password_path
  end

  test "update sets a new password" do
    patch password_path(@user.password_reset_token), params: { password: "new-password", password_confirmation: "new-password" }
    assert_redirected_to new_session_path
    assert User.authenticate_by(email_address: @user.email_address, password: "new-password")
  end

  test "update refuses a mismatched confirmation" do
    patch password_path(@user.password_reset_token), params: { password: "one", password_confirmation: "two" }
    assert_redirected_to %r{/passwords/.+/edit}
  end
end
