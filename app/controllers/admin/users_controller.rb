require "csv"

module Admin
  class UsersController < BaseController
    before_action :set_user, only: %i[ update unlock suspend activate resend_invitation ]

    def index
      @users = User.order(:id)
      respond_to do |format|
        format.html
        format.csv do
          AuditLog.record!(:export, nil, metadata: { resource: "User", rows: @users.size })
          send_data users_csv(@users), filename: "users_#{Time.current.strftime('%Y%m%d%H%M%S')}.csv", type: "text/csv; charset=utf-8"
        end
      end
    end

    def new
      @user = User.new(role: :staff)
    end

    # 招待: 使えないランダムなパスワードで invited のユーザーを作り、設定リンクをメールで送る
    def create
      @user = User.new(params.expect(user: %i[ name email_address role ]))
      @user.assign_attributes(status: :invited, password: User.unusable_password)
      if @user.save
        UsersMailer.invitation(@user).deliver_later
        AuditLog.record!(:user_invite, @user, metadata: { role: @user.role })
        redirect_to admin_users_path, notice: "#{@user.name} に招待メールを送りました。"
      else
        render :new, status: :unprocessable_entity
      end
    end

    def resend_invitation
      if @user.invited?
        UsersMailer.invitation(@user).deliver_later
        AuditLog.record!(:user_invite, @user, metadata: { resent: true })
        redirect_to admin_users_path, notice: "#{@user.name} に招待メールを再送しました。"
      else
        redirect_to admin_users_path, alert: "招待中のユーザーではありません。"
      end
    end

    # 停止: ログインできなくなり、セッションも全部切れる（User のコールバック）。自分自身は停止できない
    def suspend
      if @user == current_user
        redirect_to admin_users_path, alert: "自分自身は停止できません。"
      elsif @user.update(status: :suspended)
        AuditLog.record!(:user_suspend, @user)
        redirect_to admin_users_path, notice: "#{@user.name} を停止しました。ログイン中のセッションも切断しました。"
      else
        redirect_to admin_users_path, alert: "停止できませんでした。"
      end
    end

    def activate
      if @user.suspended?
        @user.update!(status: :active)
        AuditLog.record!(:user_activate, @user)
        redirect_to admin_users_path, notice: "#{@user.name} の停止を解除しました。"
      else
        redirect_to admin_users_path, alert: "停止中のユーザーではありません。"
      end
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
      def users_csv(users)
        body = CSV.generate do |csv|
          csv << %w[email_address name role status]
          users.each { |u| csv << [ u.email_address, u.name, u.role, u.status ].map { |v| CsvSafety.cell(v) } }
        end
        "\uFEFF#{body}"
      end

      def set_user
        @user = User.find(params[:id])
      end
  end
end
