module Admin
  # CSV で一括登録。まずプレビュー（create）で検証し、確認（confirm）で取り込む。エラーが1行でもあれば取り込まない。
  class UserImportsController < BaseController
    def new
    end

    def create
      @csv = uploaded_text
      @rows = UserCsv.parse_import(@csv)
      render :preview
    rescue UserCsv::Invalid => e
      redirect_to new_admin_user_import_path, alert: e.message
    end

    def confirm
      rows = UserCsv.parse_import(params[:csv].to_s)
      error_count = rows.count { |row| !row.valid? }
      return redirect_to(new_admin_user_import_path, alert: "エラーが#{error_count}行あるため登録できません。CSVを直してもう一度アップロードしてください。") if error_count.positive?

      created = rows.filter_map do |row|
        user = User.new(email_address: row.email, name: row.name, role: row.role, status: :invited, password: User.unusable_password)
        next unless user.save

        UsersMailer.invitation(user).deliver_later
        user
      end
      AuditLog.record!(:user_import, nil, metadata: { created: created.size, skipped: rows.size - created.size, emails: created.map(&:email_address) })
      redirect_to admin_users_path, notice: "#{created.size}人を招待しました。"
    rescue UserCsv::Invalid => e
      redirect_to new_admin_user_import_path, alert: e.message
    end

    private
      def uploaded_text
        file = params[:file]
        raise UserCsv::Invalid, "CSV ファイルを選んでください" unless file.respond_to?(:read)

        file.read(UserCsv::MAX_BYTES + 1).to_s.dup.force_encoding(Encoding::UTF_8)
      end
  end
end
