module Admin
  # CSV（メールアドレスの一覧）で一括停止。プレビュー → 確認の順。エラーのある行は停止しない。
  class UserSuspensionsController < BaseController
    def new
    end

    def create
      @csv = uploaded_text
      @rows = UserCsv.parse_suspend(@csv, current_user: current_user)
      render :preview
    rescue UserCsv::Invalid => e
      redirect_to new_admin_user_suspension_path, alert: e.message
    end

    def confirm
      rows = UserCsv.parse_suspend(params[:csv].to_s, current_user: current_user)
      suspended = rows.select(&:valid?).filter_map do |row|
        user = User.find_by(email_address: row.email)
        next unless user&.update(status: :suspended)

        AuditLog.record!(:user_suspend, user, metadata: { bulk: true })
        user
      end
      redirect_to admin_users_path, notice: "#{suspended.size}人を停止しました（エラーなどで停止しなかった行：#{rows.size - suspended.size}行）。"
    rescue UserCsv::Invalid => e
      redirect_to new_admin_user_suspension_path, alert: e.message
    end

    private
      def uploaded_text
        file = params[:file]
        raise UserCsv::Invalid, "CSV ファイルを選んでください" unless file.respond_to?(:read)

        file.read(UserCsv::MAX_BYTES + 1).to_s.dup.force_encoding(Encoding::UTF_8)
      end
  end
end
