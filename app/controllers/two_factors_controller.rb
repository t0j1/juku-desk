# 自分の 2FA（TOTP）の設定・解除。system_admin は必須なので解除できない。
class TwoFactorsController < ApplicationController
  forbid_during_impersonation # 代理ログイン中は 2FA の設定・解除をさせない
  allow_viewer_writes                # 自分のアカウントの設定は viewer にも許す
  allow_without_two_factor only: %i[ new create ] # 必須なのに未設定の人は、ここだけ使える
  before_action :redirect_if_enabled, only: %i[ new create ]
  after_action -> { response.headers["Cache-Control"] = "no-store" }, only: %i[ new create ]

  def show
  end

  def new
    @secret = session[:pending_otp_secret] ||= Totp.generate_secret
    @otpauth_uri = Totp.provisioning_uri(@secret, account: current_user.email_address, issuer: "塾日報ステーション")
  end

  def create
    secret = session[:pending_otp_secret]
    step = secret && Totp.verify(secret, params[:code])
    if step
      @recovery_codes = current_user.enable_otp!(secret, step)
      session.delete(:pending_otp_secret)
      AuditLog.record!(:two_factor_enable, current_user)
      render :recovery_codes # リダイレクトせず、この 1 回だけ表示する
    else
      redirect_to new_two_factor_path, alert: "認証コードが正しくありません。アプリの表示を確認してもう一度入力してください。"
    end
  end

  def destroy
    if current_user.two_factor_required?
      redirect_to two_factor_path, alert: "このアカウントは 2 段階認証が必須のため解除できません。"
    elsif current_user.authenticate(params[:password].to_s) && current_user.verify_second_factor(params[:code])
      current_user.disable_otp!
      AuditLog.record!(:two_factor_disable, current_user)
      redirect_to two_factor_path, notice: "2段階認証を解除しました。", status: :see_other
    else
      redirect_to two_factor_path, alert: "パスワードまたは認証コードが正しくありません。"
    end
  end

  private
    def redirect_if_enabled
      redirect_to two_factor_path if current_user.otp_enabled?
    end
end
