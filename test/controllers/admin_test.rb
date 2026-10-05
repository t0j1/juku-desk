require "test_helper"

class AdminTest < ActionDispatch::IntegrationTest
  test "staff and viewer cannot open admin screens" do
    [ users(:staff), users(:viewer) ].each do |u|
      sign_in_as u
      get admin_users_path
      assert_redirected_to root_path
      get admin_login_events_path
      assert_redirected_to root_path
    end
  end

  test "admin lists users and changes a role, which is audited" do
    sign_in_as users(:system_admin)
    get admin_users_path
    assert_response :success

    assert_difference -> { AuditLog.where(action: "role_change").count }, 1 do
      patch admin_user_path(users(:staff)), params: { user: { role: "viewer" } }
    end
    assert users(:staff).reload.viewer?
  end

  test "admin cannot change own role or set an unknown role" do
    sign_in_as users(:system_admin)
    patch admin_user_path(users(:system_admin)), params: { user: { role: "viewer" } }
    assert users(:system_admin).reload.system_admin?
    patch admin_user_path(users(:staff)), params: { user: { role: "root" } }
    assert users(:staff).reload.staff?
  end

  test "unlock is audited" do
    5.times { users(:staff).register_failed_login! }
    sign_in_as users(:system_admin)
    assert_difference -> { AuditLog.where(action: "unlock").count }, 1 do
      post unlock_admin_user_path(users(:staff))
    end
    assert_not users(:staff).reload.locked?
  end

  test "login events can be searched and exported as CSV (audited, formula-safe)" do
    LoginEvent.create!(email_address: "=cmd|x@example.com", success: false, reason: "invalid_credentials", ip_address: "203.0.113.9", user_agent: "UA")
    LoginEvent.create!(email_address: "ok@example.com", success: true, ip_address: "198.51.100.2", user_agent: "UA")
    sign_in_as users(:system_admin)

    get admin_login_events_path, params: { q: "203.0.113" }
    assert_response :success
    assert_select "#login_events tbody tr", 1

    get admin_login_events_path, params: { result: "success" }
    assert_select "#login_events tbody tr", 1

    assert_difference -> { AuditLog.where(action: "export").count }, 1 do
      get admin_login_events_path(format: :csv)
    end
    assert_response :success
    assert_match "text/csv", response.media_type
    assert_includes response.body, "'=cmd|x@example.com"
    assert_includes response.body, "ok@example.com"
  end
end
