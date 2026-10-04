require "test_helper"

class AdminUserOpsTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper

  setup { sign_in_as users(:system_admin) }

  def csv_file(text, name: "users.csv")
    Rack::Test::UploadedFile.new(StringIO.new(text), "text/csv", original_filename: name)
  end

  # --- R1: 状態・招待 ---

  test "inviting creates an invited user, sends mail, audited; the user sets a password and can log in" do
    assert_difference "User.count", 1 do
      assert_enqueued_emails 1 do
        post admin_users_path, params: { user: { name: "新人 一郎", email_address: "new@example.com", role: "viewer" } }
      end
    end
    user = User.find_by!(email_address: "new@example.com")
    assert user.invited?
    assert user.viewer?
    assert AuditLog.exists?(action: "user_invite", auditable: user)

    # 招待中はまだログインできない
    delete session_path
    post session_path, params: { email_address: user.email_address, password: "Not The Password 1" }
    assert_nil cookies[:session_id].presence

    token = user.generate_token_for(:invitation)
    get edit_invitation_path(token)
    assert_response :success
    put invitation_path(token), params: { password: "Blue Moon Rises 7", password_confirmation: "Blue Moon Rises 7" }
    assert_redirected_to new_session_path
    assert user.reload.active?

    post session_path, params: { email_address: user.email_address, password: "Blue Moon Rises 7" }
    assert_redirected_to root_path
  end

  test "invitation mail contains the set-password link" do
    mail = UsersMailer.invitation(users(:invited))
    assert_equal [ users(:invited).email_address ], mail.to
    assert_match %r{http://example\.com/invitations/[^/\s]+/edit}, mail.text_part.body.to_s
  end

  test "invitation link: weak password is refused, token dies after use, expired or suspended users are refused" do
    user = users(:invited)
    token = user.generate_token_for(:invitation)
    put invitation_path(token), params: { password: "short", password_confirmation: "short" }
    assert_redirected_to edit_invitation_path(token)
    assert user.reload.invited?

    put invitation_path(token), params: { password: "Blue Moon Rises 7", password_confirmation: "Blue Moon Rises 7" }
    get edit_invitation_path(token)
    assert_redirected_to new_session_path, "used token is dead"

    other = User.create!(name: "x", email_address: "late@example.com", password: User.unusable_password, status: :invited)
    stale = other.generate_token_for(:invitation)
    travel 8.days do
      get edit_invitation_path(stale)
      assert_redirected_to new_session_path
    end
    User.find(other.id).update!(status: :suspended)
    get edit_invitation_path(other.generate_token_for(:invitation))
    assert_redirected_to new_session_path
    get edit_invitation_path("garbage")
    assert_redirected_to new_session_path
  end

  test "resend invitation only for invited users" do
    assert_enqueued_emails 1 do
      post resend_invitation_admin_user_path(users(:invited))
    end
    assert_enqueued_emails 0 do
      post resend_invitation_admin_user_path(users(:staff))
    end
  end

  test "suspending cuts every session at once, blocks login, is audited; activating restores" do
    victim = users(:staff)
    sessions = 2.times.map { victim.sessions.create! }
    assert_difference -> { AuditLog.where(action: "user_suspend").count }, 1 do
      post suspend_admin_user_path(victim)
    end
    assert victim.reload.suspended?
    assert_equal 0, victim.sessions.count
    sessions.each { |s| assert_not Session.exists?(s.id) }

    delete session_path
    post session_path, params: { email_address: victim.email_address, password: "password" }
    assert_nil cookies[:session_id].presence

    sign_in_as users(:system_admin)
    post activate_admin_user_path(victim)
    assert victim.reload.active?
    assert AuditLog.exists?(action: "user_activate", auditable: victim)
  end

  test "an admin cannot suspend themselves; staff cannot use these screens" do
    post suspend_admin_user_path(users(:system_admin))
    assert users(:system_admin).reload.active?

    sign_in_as users(:staff)
    post suspend_admin_user_path(users(:viewer))
    assert users(:viewer).reload.active?
    get new_admin_user_path
    assert_redirected_to root_path
  end

  test "suspended user's password reset mail is not sent" do
    delete session_path
    assert_enqueued_emails 0 do
      post passwords_path, params: { email_address: users(:inactive).email_address }
    end
  end

  # --- R2: CSV ---

  test "import preview lists errors and writes nothing" do
    csv = <<~CSV
      email_address,name,role
      ok1@example.com,山田,staff
      ok2@example.com,佐藤,viewer
      not-an-email,鈴木,staff
      #{users(:staff).email_address},既存,staff
      ok1@example.com,重複,staff
      bad-role@example.com,権限,boss
      no-name@example.com,,staff
    CSV
    assert_no_difference "User.count" do
      post admin_user_import_path, params: { file: csv_file(csv) }
    end
    assert_response :success
    assert_select "#import-summary", /7行中、取り込めるのは 2行、エラーは 5行/
    assert_select "tr.bg-ng-bg", 5
  end

  test "import confirm creates only the valid rows as invited users and mails them" do
    csv = "email_address,name,role\nok1@example.com,山田,staff\nbroken,壊れ,staff\nok2@example.com,佐藤,\n"
    assert_difference "User.count", 2 do
      assert_enqueued_emails 2 do
        post confirm_admin_user_import_path, params: { csv: csv }
      end
    end
    assert User.find_by!(email_address: "ok1@example.com").invited?
    assert User.find_by!(email_address: "ok2@example.com").staff?
    assert_nil User.find_by(email_address: "broken")
    assert AuditLog.exists?(action: "user_import")
  end

  test "import accepts Japanese headers and a BOM, rejects bad files" do
    csv = "﻿メールアドレス,氏名,権限\nj@example.com,日本語,閲覧のみ\n"
    post admin_user_import_path, params: { file: csv_file(csv) }
    assert_select "#import-summary", /1行中、取り込めるのは 1行/

    post admin_user_import_path, params: { file: csv_file("foo,bar\n1,2\n") }
    assert_redirected_to new_admin_user_import_path
    post admin_user_import_path, params: { file: csv_file("") }
    assert_redirected_to new_admin_user_import_path
    post admin_user_import_path
    assert_redirected_to new_admin_user_import_path
    post admin_user_import_path, params: { file: csv_file("email_address,name\n" + ("a@example.com,x\n" * 501)) }
    assert_redirected_to new_admin_user_import_path
  end

  test "bulk suspend preview skips unknown, self and already suspended; confirm suspends the rest" do
    csv = "email_address\n#{users(:staff).email_address}\nnobody@example.com\n#{users(:system_admin).email_address}\n#{users(:inactive).email_address}\n"
    post admin_user_suspension_path, params: { file: csv_file(csv) }
    assert_select "#suspend-summary", /4行中、停止するのは 1人、エラーは 3行/
    assert users(:staff).reload.active?

    session = users(:staff).sessions.create!
    post confirm_admin_user_suspension_path, params: { csv: csv }
    assert users(:staff).reload.suspended?
    assert_not Session.exists?(session.id)
    assert users(:system_admin).reload.active?
  end

  test "bulk suspend accepts a plain list of addresses" do
    post admin_user_suspension_path, params: { file: csv_file("#{users(:staff).email_address}\n#{users(:viewer).email_address}\n") }
    assert_select "#suspend-summary", /2行中、停止するのは 2人/
  end

  test "export is a CSV of all users, audited and formula-safe" do
    users(:viewer).update_columns(name: "=HYPERLINK(1)")
    assert_difference -> { AuditLog.where(action: "export").count }, 1 do
      get admin_users_path(format: :csv)
    end
    assert_match "text/csv", response.media_type
    assert_includes response.body, "email_address,name,role,status"
    assert_includes response.body, users(:staff).email_address
    assert_includes response.body, "'=HYPERLINK(1)"
  end
end
