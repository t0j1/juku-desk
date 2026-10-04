# ログイン中の 2 段階目（パスワードは通過済み）。TOTP かリカバリーコードを受け付ける。
class TwoFactorChallengesController < ApplicationController
  PENDING_TTL = 5.minutes

  allow_unauthenticated_access
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to new_session_path, alert: "しばらくしてから再度お試しください。" }
  before_action :load_pending_user

  def new
  end

  def create
    if @user.locked?
      LoginEvent.record!(email_address: @user.email_address, user: @user, success: false, reason: "locked", request: request)
      return abort_challenge
    end

    kind = @user.verify_second_factor(params[:code])
    if kind
      session.delete(:pending_two_factor)
      complete_login!(@user)
      AuditLog.record!(:recovery_code_used, @user, user: @user, metadata: { remaining: @user.recovery_codes.unused.count }) if kind == :recovery
      redirect_to after_authentication_url
    else
      # コードの総当たりもパスワードと同じ失敗回数に数える
      became_locked = @user.register_failed_login!
      LoginEvent.record!(email_address: @user.email_address, user: @user, success: false, reason: "invalid_otp", request: request)
      AuditLog.record!(:lock, @user, user: @user, metadata: { failed_attempts: @user.failed_attempts, locked_until: @user.locked_until }) if became_locked
      if became_locked
        abort_challenge
      else
        redirect_to new_two_factor_challenge_path, alert: "認証コードが正しくありません。"
      end
    end
  end

  private
    def load_pending_user
      pending = session[:pending_two_factor]
      user = User.find_by(id: pending["user_id"]) if pending && Time.current.to_i - pending["at"].to_i <= PENDING_TTL
      if user&.active? && user.otp_enabled?
        @user = user
      else
        session.delete(:pending_two_factor)
        redirect_to new_session_path, alert: "もう一度ログインしてください。"
      end
    end

    def abort_challenge
      session.delete(:pending_two_factor)
      redirect_to new_session_path, alert: SessionsController::FAILURE_MESSAGE
    end
end
