require "test_helper"

class UserSessionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:staff)
    sign_in_as @user
    @other = @user.sessions.create!(ip_address: "203.0.113.5", user_agent: "iPad")
  end

  test "lists devices and IPs" do
    get user_sessions_path
    assert_response :success
    assert_select "#session_#{@other.id}", /203\.0\.113\.5/
  end

  test "revoked session is sent back to login on the next request" do
    assert_difference -> { @user.sessions.count }, -1 do
      delete user_session_path(@other)
    end
    assert_redirected_to user_sessions_path
    assert_not Session.exists?(@other.id)
  end

  test "revoking the current session logs out" do
    delete user_session_path(Current.session)
    assert_redirected_to new_session_path
    get students_path
    assert_redirected_to new_session_path
  end

  test "revoke all others keeps only this device and is audited" do
    @user.sessions.create!
    assert_difference -> { AuditLog.where(action: "revoke_session").count }, 1 do
      delete destroy_others_user_sessions_path
    end
    assert_equal [ Current.session.id ], @user.sessions.pluck(:id)
  end

  test "cannot revoke someone else's session" do
    foreign = users(:system_admin).sessions.create!
    delete user_session_path(foreign)
    assert_response :not_found
    assert Session.exists?(foreign.id)
  end

  test "a revoked browser session is rejected" do
    victim_session = @user.sessions.create!
    victim_session.destroy!
    # cookie に残っていても Session が無いので認証されない
    cookies[:session_id] = ActionDispatch::TestRequest.create.cookie_jar.tap { |j| j.signed[:session_id] = victim_session.id }[:session_id]
    get students_path
    assert_redirected_to new_session_path
  end
end
