require "test_helper"

class AdminMailTemplatesTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:system_admin) }

  def body_with_url(extra = "")
    "{{name}} さん\n#{extra}\n{{url}}\n"
  end

  test "only system_admin can open the screens" do
    [ users(:staff), users(:viewer) ].each do |u|
      sign_in_as u
      get admin_mail_templates_path
      assert_redirected_to root_path
      patch admin_mail_template_path("invitation"), params: { mail_template: { subject: "x", body: body_with_url } }
      assert_equal 0, MailTemplate.count
    end
  end

  test "index lists both templates as defaults" do
    get admin_mail_templates_path
    assert_select "#mail_template_invitation", /招待メール/
    assert_select "#mail_template_password_reset", /パスワードリセット/
    assert_select "#mail_templates", /初期値/
  end

  test "editing saves, is audited, and the mailer uses it (text and html, escaped)" do
    assert_difference -> { AuditLog.where(action: "mail_template_update").count }, 1 do
      patch admin_mail_template_path("invitation"), params: { mail_template: { subject: "ようこそ {{name}} さん", body: body_with_url("<b>注意</b> & 7日以内に") } }
    end
    assert_redirected_to admin_mail_templates_path
    assert_equal users(:system_admin), MailTemplate.find_by!(key: "invitation").updated_by

    mail = UsersMailer.invitation(users(:invited))
    assert_equal "ようこそ 招待 四郎 さん", mail.subject
    assert_includes mail.text_part.body.to_s, "<b>注意</b> & 7日以内に"
    html = mail.html_part.body.to_s
    assert_includes html, "&lt;b&gt;注意&lt;/b&gt; &amp; 7日以内に"
    assert_not_includes html, "<b>注意</b>"
    assert_match %r{<a href="http://example\.com/invitations/[^"]+/edit">}, html
  end

  test "the password reset mail uses its template too" do
    MailTemplate.create!(key: "password_reset", subject: "再設定: {{name}}", body: body_with_url("期限 {{expires}}"))
    mail = PasswordsMailer.reset(users(:staff))
    assert_equal "再設定: #{users(:staff).name}", mail.subject
    assert_includes mail.text_part.body.to_s, "期限 15分間"
    assert_match %r{http://example\.com/passwords/[^/\s]+/edit}, mail.text_part.body.to_s
  end

  test "defaults are used when nothing is saved, and contain the link" do
    mail = UsersMailer.invitation(users(:invited))
    assert_includes mail.subject, "招待"
    assert_match %r{/invitations/[^/\s]+/edit}, mail.text_part.body.to_s
    assert_includes mail.text_part.body.to_s, "7日間有効"
    assert_no_match(/\{\{/, mail.text_part.body.to_s)
  end

  test "preview renders with sample values and saves nothing" do
    assert_no_difference "MailTemplate.count" do
      post preview_admin_mail_template_path("invitation"), params: { mail_template: { subject: "件名 {{name}}", body: body_with_url("期間 {{expires}}") } }
    end
    assert_response :success
    assert_select "#mail-preview", /件名 山田 太郎/
    assert_select "#mail-preview", /期間 7日間/
    assert_select "#mail-preview", /https:\/\/example\.com\/invitations\/SAMPLE\/edit/
  end

  test "preview of an invalid draft shows errors-free preview but flags it" do
    post preview_admin_mail_template_path("invitation"), params: { mail_template: { subject: "x", body: "リンクなし" } }
    assert_select "#mail-preview", /保存できません/
  end

  test "unknown placeholders and a missing {{url}} are refused" do
    patch admin_mail_template_path("invitation"), params: { mail_template: { subject: "x {{secret}}", body: body_with_url } }
    assert_response :unprocessable_entity
    assert_select "#error_explanation", /\{\{secret\}\}/

    patch admin_mail_template_path("invitation"), params: { mail_template: { subject: "x", body: "リンクなし" } }
    assert_response :unprocessable_entity
    assert_select "#error_explanation", /\{\{url\}\}/
    assert_equal 0, MailTemplate.count
  end

  test "values are not re-expanded and subject newlines are removed" do
    template = MailTemplate.new(key: "invitation", subject: "a\r\nBcc: x@evil.example {{name}}", body: "{{url}}")
    rendered = template.render("name" => "{{url}}", "url" => "U", "expires" => "E")
    assert_equal "a Bcc: x@evil.example {{url}}", rendered.subject
    assert_not_includes rendered.subject, "\n"
    assert_equal "U", rendered.body
  end

  test "reset returns to the defaults, audited; unknown keys 404" do
    MailTemplate.create!(key: "invitation", subject: "s", body: "{{url}}")
    assert_difference -> { AuditLog.where(action: "mail_template_reset").count }, 1 do
      post reset_admin_mail_template_path("invitation")
    end
    assert_equal 0, MailTemplate.count
    get edit_admin_mail_template_path("nope")
    assert_response :not_found
  end
end
