require "test_helper"

class LoginHardeningTest < ActionDispatch::IntegrationTest
  setup { @user = users(:staff) }

  def login(password)
    post session_path, params: { email_address: @user.email_address, password: password }
  end

  test "sixth attempt is refused even with the correct password" do
    5.times { login("wrong-password") }
    assert @user.reload.locked?

    login("password")
    assert_redirected_to new_session_path
    assert_nil cookies[:session_id].presence
  end

  test "login works again right after an admin unlocks" do
    5.times { login("wrong-password") }
    sign_in_as users(:system_admin)
    post unlock_admin_user_path(@user)
    delete session_path

    login("password")
    assert_redirected_to root_path
    assert cookies[:session_id].present?
  end

  test "success resets the failure counter" do
    3.times { login("wrong-password") }
    login("password")
    assert_equal 0, @user.reload.failed_attempts
  end

  test "attempts are recorded as login events (success, failure, locked)" do
    login("wrong-password")
    login("password")
    assert_equal [ false, true ], LoginEvent.order(:id).last(2).map(&:success)
    event = LoginEvent.order(:id).last
    assert_equal @user.email_address, event.email_address
    assert_equal @user, event.user
    assert event.ip_address.present?
  end

  test "unknown email is recorded without a user and does not reveal itself" do
    post session_path, params: { email_address: "nobody@example.com", password: "x" }
    assert_redirected_to new_session_path
    assert_nil LoginEvent.last.user
    assert_equal "invalid_credentials", LoginEvent.last.reason
  end

  test "locking is audited" do
    assert_difference -> { AuditLog.where(action: "lock").count }, 1 do
      5.times { login("wrong-password") }
    end
  end
end
