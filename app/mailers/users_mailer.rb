class UsersMailer < ApplicationMailer
  # 招待メール。リンクから初期パスワードを設定する。文面は MailTemplate（管理画面で編集できる）
  def invitation(user)
    url = edit_invitation_url(user.generate_token_for(:invitation))
    template_mail("invitation", user, url: url, expires: "7日間")
  end
end
