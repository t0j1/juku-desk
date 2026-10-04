module Admin
  class UsersController < BaseController
    before_action :set_user, only: %i[ update unlock reset_two_factor ]

    def index
      @users = User.order(:id)
    end

    # 権限の変更。自分自身は変えられない（最後の system_admin を失って締め出されるのを防ぐ）
    def update
      new_role = params.expect(user: [ :role ])[:role]
      if @user == current_user
        redirect_to admin_users_path, alert: "自分自身の権限は変更できません。"
      elsif User.roles.key?(new_role) && @user.update(role: new_role)
        if @user.saved_change_to_role?
          AuditLog.record!(:role_change, @user, metadata: { from: @user.role_before_last_save, to: @user.role })
        end
        redirect_to admin_users_path, notice: "#{@user.name} の権限を変更しました。"
      else
        redirect_to admin_users_path, alert: "権限を変更できませんでした。"
      end
    end

    def unlock
      @user.unlock!
      AuditLog.record!(:unlock, @user)
      redirect_to admin_users_path, notice: "#{@user.name} のロックを解除しました。"
    end

    # 2FA のリセット（端末を失くしたとき）。次のログインで再設定を求める。自分自身は別の管理者に頼む。
    def reset_two_factor
      if @user == current_user
        redirect_to admin_users_path, alert: "自分自身の 2 段階認証はリセットできません。ほかの管理者に依頼してください。"
      else
        @user.reset_otp!
        @user.sessions.destroy_all
        AuditLog.record!(:two_factor_reset, @user)
        redirect_to admin_users_path, notice: "#{@user.name} の 2 段階認証をリセットしました。次のログインで再設定が必要です。"
      end
    end

    private
      def set_user
        @user = User.find(params[:id])
      end
  end
end
