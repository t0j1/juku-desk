require "test_helper"

class PasswordsControllerTest < ActionDispatch::IntegrationTest
  setup { @user = users(:staff) }

  test "new" do
    get new_password_path
    assert_response :success
  end

  test "create" do
    post passwords_path, params: { email_address: @user.email_address }
    assert_enqueued_email_with PasswordsMailer, :reset, args: [ @user ]
    assert_redirected_to new_session_path

    follow_redirect!
    assert_notice "再設定の案内を送信しました"
  end

  test "create for an unknown user redirects but sends no mail" do
    post passwords_path, params: { email_address: "missing-user@example.com" }
    assert_enqueued_emails 0
    assert_redirected_to new_session_path

    follow_redirect!
    assert_notice "再設定の案内を送信しました"
  end

  test "edit" do
    get edit_password_path(@user.password_reset_token)
    assert_response :success
  end

  test "edit with invalid password reset token" do
    get edit_password_path("invalid token")
    assert_redirected_to new_password_path

    follow_redirect!
    assert_select "#alert", /再設定リンクが無効/
  end

  test "update" do
    assert_changes -> { @user.reload.password_digest } do
      put password_path(@user.password_reset_token), params: { password: "Blue Moon Rises 7", password_confirmation: "Blue Moon Rises 7" }
      assert_redirected_to new_session_path
    end

    follow_redirect!
    assert_notice "パスワードを再設定しました"
  end

  test "update unlocks a locked account" do
    5.times { @user.register_failed_login! }
    assert @user.reload.locked?
    put password_path(@user.password_reset_token), params: { password: "Blue Moon Rises 7", password_confirmation: "Blue Moon Rises 7" }
    assert_not @user.reload.locked?
    assert_equal 0, @user.failed_attempts
  end

  test "update rejects a weak password and a reused one" do
    token = @user.password_reset_token
    put password_path(token), params: { password: "short1", password_confirmation: "short1" }
    assert_redirected_to edit_password_path(token)
    follow_redirect!
    assert_select "#alert", /12文字以上/

    put password_path(token), params: { password: "password", password_confirmation: "password" }
    assert_redirected_to edit_password_path(token)
  end

  test "update is audited" do
    assert_difference -> { AuditLog.where(action: "password_change").count }, 1 do
      put password_path(@user.password_reset_token), params: { password: "Blue Moon Rises 7", password_confirmation: "Blue Moon Rises 7" }
    end
  end

  test "update with non matching passwords" do
    token = @user.password_reset_token
    assert_no_changes -> { @user.reload.password_digest } do
      put password_path(token), params: { password: "Aa1 first pass x", password_confirmation: "Aa1 other pass y" }
      assert_redirected_to edit_password_path(token)
    end

    follow_redirect!
    assert_select "#alert", /入力が一致しません/
  end

  private
    def assert_notice(text)
      assert_select "#notice", /#{text}/
    end
end
