require "test_helper"

class ImpersonationTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:system_admin)
    @staff = users(:staff)
  end

  def start_as_admin(user = @staff, reason: "問い合わせ対応")
    sign_in_as @admin
    post admin_user_impersonation_path(user), params: { reason: reason }
  end

  test "system_admin が理由つきで代理ログインを開始できる" do
    assert_difference -> { AuditLog.where(action: "impersonation_start").count }, 1 do
      start_as_admin
    end
    assert_redirected_to root_path
    log = AuditLog.where(action: "impersonation_start").last
    assert_equal @staff, log.user
    assert_equal @admin, log.impersonator
    assert_equal "問い合わせ対応", log.metadata["reason"]

    get students_path
    assert_select "#impersonation-banner", text: /#{@staff.name}/
    assert_select "#impersonation-banner button", text: "元に戻る"
  end

  test "理由が空だと開始できない" do
    sign_in_as @admin
    assert_no_difference "Session.count" do
      post admin_user_impersonation_path(@staff), params: { reason: "  " }
    end
    assert_response :unprocessable_entity
    assert_equal 0, AuditLog.where(action: "impersonation_start").count
  end

  test "system_admin 以外は開始できない" do
    sign_in_as @staff
    post admin_user_impersonation_path(users(:viewer)), params: { reason: "x" }
    assert_equal 0, Session.where.not(impersonator_id: nil).count
  end

  test "自分自身・system_admin・停止中のユーザーには代理ログインできない" do
    sign_in_as @admin
    [ @admin, users(:inactive), users(:invited) ].each do |target|
      post admin_user_impersonation_path(target), params: { reason: "x" }
      assert_redirected_to admin_users_path
    end
    assert_equal 0, Session.where.not(impersonator_id: nil).count
  end

  test "代理ログイン中は対象ユーザーの権限になり、管理画面に入れない" do
    start_as_admin
    get admin_users_path
    assert_response :redirect
    assert_not_equal admin_users_path, response.location
  end

  test "元に戻るで管理者のセッションに戻り、終了が監査ログに残る" do
    start_as_admin
    assert_difference -> { AuditLog.where(action: "impersonation_end").count }, 1 do
      delete impersonation_path
    end
    assert_redirected_to admin_users_path
    log = AuditLog.where(action: "impersonation_end").last
    assert_equal @admin, log.impersonator
    assert_equal "manual", log.metadata["via"]

    follow_redirect!
    assert_response :success
    assert_select "#impersonation-banner", count: 0
    assert_equal 0, Session.where.not(impersonator_id: nil).count
  end

  test "30分たつと自動的に終了して管理者に戻る" do
    start_as_admin
    travel 31.minutes do
      get students_path
      assert_response :success
      assert_select "#impersonation-banner", count: 0
      end_log = AuditLog.where(action: "impersonation_end").last
      assert_equal "expired", end_log.metadata["via"]
      get admin_users_path
      assert_response :success # 管理者に戻っている
    end
  end

  test "期限切れのあとのリクエストは実行されず、管理者に戻って管理画面へリダイレクトされる" do
    student = students(:one) rescue Student.first
    start_as_admin
    travel 31.minutes do
      assert_no_changes -> { student.reload.name } do
        patch student_path(student), params: { student: { name: "書き換え" } }
      end
      assert_redirected_to admin_users_path
      assert_equal 0, AuditLog.where(action: "update", user: @admin).count
      follow_redirect!
      assert_response :success # Cookie は管理者に戻っている
    end
  end

  test "拒否された操作も監査ログに残る" do
    start_as_admin
    assert_difference -> { AuditLog.where(action: "impersonated_request", impersonator_id: @admin.id).count }, 1 do
      delete two_factor_path, params: { password: "password", code: "000000" }
    end
    log = AuditLog.where(action: "impersonated_request").last
    assert_equal "/two_factor", log.metadata["path"]
    assert_equal 302, log.metadata["status"]
  end

  test "viewer として拒否された書き込みも監査ログに残る" do
    sign_in_as @admin
    post admin_user_impersonation_path(users(:viewer)), params: { reason: "確認" }
    assert_difference -> { AuditLog.where(action: "impersonated_request").count }, 1 do
      post students_path, params: { student: { name: "x" } }
    end
    assert_equal 403, AuditLog.where(action: "impersonated_request").last.metadata["status"]
  end

  test "代理ログイン中の操作は管理者の ID つきで監査ログに残る" do
    start_as_admin
    assert_difference -> { AuditLog.where(action: "impersonated_request", impersonator_id: @admin.id).count }, 1 do
      get students_path
    end
    log = AuditLog.where(action: "impersonated_request").last
    assert_equal @staff, log.user
    assert_equal "/students", log.metadata["path"]
    # ふつうの操作の監査ログにも管理者の ID が入る
    assert AuditLog.where(action: "view", impersonator_id: @admin.id).exists?
  end

  test "代理ログイン中は 2FA の設定・解除とパスワード再設定ができない" do
    start_as_admin
    get new_two_factor_path
    assert_redirected_to root_path
    delete two_factor_path, params: { password: "password", code: "000000" }
    assert_redirected_to root_path
    get new_password_path
    assert_redirected_to root_path
    token = @staff.password_reset_token
    new_password = "#{SecureRandom.hex(8)}Aa1"
    patch password_path(token), params: { password: new_password, password_confirmation: new_password }
    assert_redirected_to root_path
    assert @staff.reload.authenticate("password")
  end

  test "代理ログイン中は schedule-web 用のトークンを発行しない" do
    ENV["SUPABASE_JWT_SECRET"] = SecureRandom.hex(32)
    start_as_admin
    post schedule_token_path
    assert_response :forbidden
    Current.session = Session.find_by(impersonator_id: @admin.id)
    assert_nil SupabaseToken.issue(@staff)
  ensure
    ENV.delete("SUPABASE_JWT_SECRET")
    Current.reset
  end

  test "代理ログイン中のログアウトで、代理ログインも管理者のセッションも終わる" do
    start_as_admin
    delete session_path
    assert_redirected_to new_session_path
    assert_equal 0, Session.where.not(impersonator_id: nil).count
    assert_equal 0, @admin.sessions.count
    assert_equal "logout", AuditLog.where(action: "impersonation_end").last.metadata["via"]
  end

  test "代理ログイン中に管理者が停止されたら無効になる" do
    start_as_admin
    @admin.update_columns(status: User.statuses[:suspended])
    get root_path
    assert_redirected_to new_session_path
  end

  test "ふつうのログインでは赤い帯が出ない" do
    sign_in_as @staff
    get students_path
    assert_select "#impersonation-banner", count: 0
  end
end
