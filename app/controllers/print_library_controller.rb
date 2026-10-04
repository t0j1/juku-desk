# 講師ログイン時の印刷ページ。一覧は自分の分割済みファイル（既存の権限どおり）
class PrintLibraryController < ApplicationController
  before_action :require_system_admin!, only: :reissue

  def index
    @query = params[:q].to_s
    @jobs = current_user.pdf_split_jobs.printable(@query).limit(100)
    @print_link = PrintLink.current if current_user.system_admin?
  end

  def reissue
    link = PrintLink.reissue!(by: current_user)
    AuditLog.record!(:update, link, metadata: { print_link: "reissued" })
    redirect_to print_library_path, notice: "印刷リンクを再発行しました。古いリンクは使えなくなりました。", status: :see_other
  end
end
