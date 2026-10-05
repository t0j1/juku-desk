class SessionsController < ApplicationController
  allow_unauthenticated_access only: %i[ new create ]
  allow_viewer_writes only: :destroy
  allow_without_two_factor only: :destroy
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to new_session_path, alert: "しばらくしてから再度お試しください。" }

  DUMMY_DIGEST = BCrypt::Password.create("dummy-password").freeze
  FAILURE_MESSAGE = "メールアドレスまたはパスワードが正しくありません。続けて失敗するとアカウントが一時的にロックされます。".freeze

  def new
  end

  def create
    email = params[:email_address].to_s
    user = User.find_by(email_address: email.strip.downcase)
    # どの経路でも bcrypt を1回通し、応答時間から「登録済みか・ロック中か」が分からないようにする
    password_ok = user ? user.authenticate(params[:password].to_s) : BCrypt::Password.new(DUMMY_DIGEST).is_password?(params[:password].to_s)

    if user&.locked?
      # ロック中は正しいパスワードでも通さない（失敗回数も増やさない）
      log_attempt(email, user, success: false, reason: "locked")
      reject_login
    elsif user&.active? && password_ok
      if user.otp_enabled?
        # 2FA が有効な人は、コードを通るまでセッションを作らない（失敗回数もここでは戻さない）
        session[:pending_two_factor] = { "user_id" => user.id, "at" => Time.current.to_i }
        redirect_to new_two_factor_challenge_path
      else
        complete_login!(user)
        redirect_to after_authentication_url
      end
    else
      became_locked = user&.register_failed_login!
      log_attempt(email, user, success: false, reason: user && !user.active? ? user.status : "invalid_credentials")
      AuditLog.record!(:lock, user, user: user, metadata: { failed_attempts: user.failed_attempts, locked_until: user.locked_until }) if became_locked
      reject_login
    end
  end

  def destroy
    if impersonating?
      # 代理ログイン中のログアウト：代理ログインを終わらせてから、管理者本人の Session も閉じる
      end_impersonation!(Current.session, via: "logout")
    end
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
