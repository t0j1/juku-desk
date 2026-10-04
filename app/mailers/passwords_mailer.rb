class PasswordsMailer < ApplicationMailer
  def reset(user)
    url = edit_password_url(user.password_reset_token)
    template_mail("password_reset", user, url: url, expires: "#{user.password_reset_token_expires_in.to_i / 60}分間")
  end
end
