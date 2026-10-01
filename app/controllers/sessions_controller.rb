class SessionsController < ApplicationController
  allow_unauthenticated_access only: %i[ new create ]
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to new_session_path, alert: "しばらくしてから再度お試しください。" }

  def new
  end

  def create
    user = User.authenticate_by(params.permit(:email_address, :password))
    if user&.active?
      start_new_session_for user
      AuditLog.record!(:login, user, user: user)
      redirect_to after_authentication_url
    else
      redirect_to new_session_path, alert: "メールアドレスまたはパスワードが正しくありません。"
    end
  end

  def destroy
    AuditLog.record!(:logout, Current.user)
    terminate_session
    redirect_to new_session_path, status: :see_other
  end
end
