module Admin
  # system_admin が、理由を添えて他のユーザーとして代理ログインする。開始・終了・その間の操作は監査ログに残る。
  class ImpersonationsController < BaseController
    before_action :set_user

    def new
    end

    def create
      reason = params[:reason].to_s.strip
      if reason.blank? || reason.length > 500
        flash.now[:alert] = reason.blank? ? "代理ログインの理由を入力してください。" : "理由は 500 文字以内で入力してください。"
        return render :new, status: :unprocessable_entity
      end

      start_impersonation!(@user, reason)
      redirect_to root_path, notice: "#{@user.name} として代理ログインしました（#{Session::IMPERSONATION_LIMIT.in_minutes.to_i}分で自動的に終了します）。", status: :see_other
    end

    private
      # 本人・system_admin・停止中や招待中のユーザーには代理ログインできない
      def set_user
        @user = User.find(params[:user_id])
        reason = if @user == current_user then "自分自身には代理ログインできません。"
        elsif @user.system_admin? then "system_admin には代理ログインできません。"
        elsif !@user.active? then "有効なユーザーにだけ代理ログインできます。"
        end
        redirect_to admin_users_path, alert: reason if reason
      end
  end
end
