class SessionsController < ApplicationController
  allow_unauthenticated_access only: %i[ new create ]
  allow_viewer_writes only: :destroy
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to new_session_path, alert: "しばらくしてから再度お試しください。" }

  FAILURE_MESSAGE = "メールアドレスまたはパスワードが正しくありません。続けて失敗するとアカウントが一時的にロックされます。".freeze

  def new
  end

  def create
    email = params[:email_address].to_s
    user = User.find_by(email_address: email.strip.downcase)

    if user&.locked?
      # ロック中は正しいパスワードでも通さない（失敗回数も増やさない）
      log_attempt(email, user, success: false, reason: "locked")
      reject_login
    elsif user&.active? && user.authenticate(params[:password].to_s)
      user.register_successful_login!
      start_new_session_for user
      log_attempt(email, user, success: true)
      AuditLog.record!(:login, user, user: user)
      redirect_to after_authentication_url
    else
      became_locked = user&.register_failed_login!
      log_attempt(email, user, success: false, reason: user && !user.active? ? user.status : "invalid_credentials")
      AuditLog.record!(:lock, user, user: user, metadata: { failed_attempts: user.failed_attempts, locked_until: user.locked_until }) if became_locked
      reject_login
    end
  end

  def destroy
    AuditLog.record!(:logout, Current.user)
    terminate_session
    redirect_to new_session_path, status: :see_other
  end

  private
    def log_attempt(email, user, success:, reason: nil)
      LoginEvent.record!(email_address: email, user: user, success: success, reason: reason, request: request)
    end

    def reject_login
      redirect_to new_session_path, alert: FAILURE_MESSAGE
    end
end
