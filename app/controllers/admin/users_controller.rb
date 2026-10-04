module Admin
  class UsersController < BaseController
    before_action :set_user, only: %i[ update unlock ]

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

    private
      def set_user
        @user = User.find(params[:id])
      end
  end
end
