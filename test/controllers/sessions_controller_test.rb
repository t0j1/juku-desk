require "test_helper"

class SessionsControllerTest < ActionDispatch::IntegrationTest
  setup { @user = users(:staff) }

  test "new" do
    get new_session_path
    assert_response :success
  end

  test "create with valid credentials" do
    post session_path, params: { email_address: @user.email_address, password: "password" }

    assert_redirected_to root_path
    assert cookies[:session_id]
  end

  test "create with invalid credentials" do
    post session_path, params: { email_address: @user.email_address, password: "wrong" }

    assert_redirected_to new_session_path
    assert_nil cookies[:session_id]
  end

  test "destroy" do
    sign_in_as(users(:staff))

    delete session_path

    assert_redirected_to new_session_path
    assert_empty cookies[:session_id]
  end
end

class SessionsAuditAndInactiveTest < ActionDispatch::IntegrationTest
  test "login is audited" do
    assert_difference -> { AuditLog.where(action: "login").count }, 1 do
      post session_path, params: { email_address: users(:staff).email_address, password: "password" }
    end
  end

  test "inactive user cannot log in" do
    post session_path, params: { email_address: users(:inactive).email_address, password: "password" }
    assert_redirected_to new_session_path
    assert_nil cookies[:session_id]
  end
end
