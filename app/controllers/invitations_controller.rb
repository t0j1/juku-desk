# 招待メールのリンク先。初期パスワードを設定して、アカウントを active にする。
class InvitationsController < ApplicationController
  allow_unauthenticated_access
  rate_limit to: 10, within: 3.minutes, only: :update, with: -> { redirect_to new_session_path, alert: "しばらくしてから再度お試しください。" }
  before_action :set_user

  def edit
  end

  def update
    @user.assign_attributes(params.permit(:password, :password_confirmation))
    @user.status = :active
    if @user.save
      AuditLog.record!(:invitation_accept, @user, user: @user, ip: request.remote_ip)
      redirect_to new_session_path, notice: "パスワードを設定しました。ログインしてください。"
    else
      redirect_to edit_invitation_path(params[:token]), alert: @user.errors.full_messages.to_sentence
    end
  end

  private
    # 招待中のユーザーのトークンだけ受け付ける（停止中・設定済みは対象外）
    def set_user
      @user = User.find_by_token_for(:invitation, params[:token])
      return if @user&.invited?

      redirect_to new_session_path, alert: "招待リンクが無効か、期限切れです。管理者に再送を依頼してください。"
    end
end
