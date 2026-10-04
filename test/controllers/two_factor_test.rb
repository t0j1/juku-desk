require "test_helper"

class TwoFactorTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:staff)
    @codes = enable_two_factor_for(@user)
  end

  def password_login(user = @user)
    post session_path, params: { email_address: user.email_address, password: "password" }
  end

  def submit_code(code)
    post two_factor_challenge_path, params: { code: code }
  end

  test "password alone does not log in a user with 2FA: no session until the code is right" do
    password_login
    assert_redirected_to new_two_factor_challenge_path
    assert_nil cookies[:session_id].presence
    get students_path
    assert_redirected_to new_session_path
  end

  test "wrong code does not log in, is recorded and counts toward the lockout" do
    password_login
    assert_difference -> { LoginEvent.where(reason: "invalid_otp").count }, 1 do
      submit_code("000000")
    end
    assert_redirected_to new_two_factor_challenge_path
    assert_nil cookies[:session_id].presence
    assert_equal 1, @user.reload.failed_attempts
  end

  test "repeated wrong codes lock the account and end the challenge" do
    password_login
    5.times { submit_code("000000") }
    assert @user.reload.locked?
    submit_code(current_totp)
    assert_redirected_to new_session_path
    assert_nil cookies[:session_id].presence
  end

  test "correct code logs in, and the same code cannot be replayed" do
    password_login
    submit_code(current_totp)
    assert_redirected_to root_path
    assert cookies[:session_id].present?

    delete session_path
    password_login
    submit_code(current_totp)
    assert_redirected_to new_two_factor_challenge_path, "a used TOTP code is rejected"
  end

  test "a recovery code works exactly once" do
    code = @codes.first
    password_login
    assert_difference -> { AuditLog.where(action: "recovery_code_used").count }, 1 do
      submit_code(code)
    end
    assert_redirected_to root_path
    delete session_path

    password_login
    submit_code(code)
    assert_redirected_to new_two_factor_challenge_path
    assert_nil cookies[:session_id].presence
    assert_equal 9, @user.recovery_codes.unused.count
  end

  test "recovery code is case/hyphen tolerant" do
    password_login
    submit_code(@codes.second.upcase.delete("-"))
    assert_redirected_to root_path
  end

  test "challenge without a password step goes back to login" do
    get new_two_factor_challenge_path
    assert_redirected_to new_session_path
  end

  test "pending challenge expires" do
    password_login
    travel 6.minutes do
      submit_code(current_totp)
      assert_redirected_to new_session_path
    end
  end

  test "a user without 2FA still logs in with just the password" do
    password_login(users(:viewer))
    assert_redirected_to root_path
  end
end

class TwoFactorSetupTest < ActionDispatch::IntegrationTest
  test "user enables TOTP: QR, confirmation code, 10 recovery codes shown once, audited" do
    user = users(:staff)
    sign_in_as user
    get new_two_factor_path
    assert_response :success
    secret = css_select("#otp-secret").first.text
    assert_select "svg"

    assert_difference -> { AuditLog.where(action: "two_factor_enable").count }, 1 do
      post two_factor_path, params: { code: Totp.code(secret) }
    end
    assert_response :success
    assert_select "#recovery-codes li", 10
    assert user.reload.otp_enabled?
    assert_equal 10, user.recovery_codes.unused.count
    assert_includes response.headers["Cache-Control"], "no-store"
    assert_not_equal secret, user.otp_secret_ciphertext, "secret is stored encrypted"
    assert_equal secret, user.otp_secret
  end

  test "wrong confirmation code does not enable" do
    user = users(:staff)
    sign_in_as user
    get new_two_factor_path
    post two_factor_path, params: { code: "000000" }
    assert_redirected_to new_two_factor_path
    assert_not user.reload.otp_enabled?
  end

  test "user disables with password and code; wrong ones fail" do
    user = users(:staff)
    enable_two_factor_for(user)
    sign_in_as user

    delete two_factor_path, params: { password: "wrong", code: current_totp }
    assert user.reload.otp_enabled?
    delete two_factor_path, params: { password: "password", code: "000000" }
    assert user.reload.otp_enabled?

    assert_difference -> { AuditLog.where(action: "two_factor_disable").count }, 1 do
      delete two_factor_path, params: { password: "password", code: current_totp }
    end
    assert_not user.reload.otp_enabled?
    assert_equal 0, user.recovery_codes.count
  end

  test "viewer can set up their own 2FA" do
    sign_in_as users(:viewer)
    get new_two_factor_path
    secret = css_select("#otp-secret").first.text
    post two_factor_path, params: { code: Totp.code(secret) }
    assert_response :success
  end

  test "system_admin without 2FA is sent to setup everywhere else, and cannot disable it" do
    admin = users(:system_admin)
    admin.disable_otp!
    sign_in_as admin

    get students_path
    assert_redirected_to new_two_factor_path
    get admin_users_path
    assert_redirected_to new_two_factor_path
    get new_two_factor_path
    assert_response :success

    delete session_path # ログアウトはできる
    assert_redirected_to new_session_path
  end

  test "system_admin cannot disable 2FA" do
    admin = users(:system_admin)
    sign_in_as admin
    delete two_factor_path, params: { password: "password", code: current_totp }
    assert admin.reload.otp_enabled?
  end

  test "system_admin with 2FA logs in with a code like anyone else" do
    post session_path, params: { email_address: users(:system_admin).email_address, password: "password" }
    assert_redirected_to new_two_factor_challenge_path
  end
end

class TwoFactorAdminResetTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:staff)
    enable_two_factor_for(@user)
  end

  test "admin resets another user's 2FA: audited, sessions dropped, setup demanded at next login" do
    victim_session = @user.sessions.create!
    sign_in_as users(:system_admin)

    assert_difference -> { AuditLog.where(action: "two_factor_reset").count }, 1 do
      post reset_two_factor_admin_user_path(@user)
    end
    @user.reload
    assert_not @user.otp_enabled?
    assert @user.otp_setup_required?
    assert_equal 0, @user.recovery_codes.count
    assert_not Session.exists?(victim_session.id)
    assert_equal @user, AuditLog.where(action: "two_factor_reset").last.auditable

    delete session_path
    post session_path, params: { email_address: @user.email_address, password: "password" }
    assert_redirected_to root_path
    get students_path
    assert_redirected_to new_two_factor_path, "setup is demanded on the next login"
  end

  test "setup requirement ends once 2FA is enabled again" do
    @user.reset_otp!
    sign_in_as @user
    get new_two_factor_path
    secret = css_select("#otp-secret").first.text
    post two_factor_path, params: { code: Totp.code(secret) }
    assert_not @user.reload.otp_setup_required?
    get students_path
    assert_response :success
  end

  test "an admin cannot reset their own 2FA; staff and viewer cannot reset anyone" do
    sign_in_as users(:system_admin)
    post reset_two_factor_admin_user_path(users(:system_admin))
    assert users(:system_admin).reload.otp_enabled?

    sign_in_as users(:staff)
    post reset_two_factor_admin_user_path(users(:viewer))
    assert_redirected_to root_path
  end
end
