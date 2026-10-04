class UsersMailer < ApplicationMailer
  # 招待メール。リンクから初期パスワードを設定する
  def invitation(user)
    @user = user
    @url = edit_invitation_url(user.generate_token_for(:invitation))
    mail subject: "【塾日報ステーション】アカウントの招待", to: user.email_address
  end
end
