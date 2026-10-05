# 進捗モーダルが読む JSON。自分の処理だけ見える。
class ProgressesController < ApplicationController
  # 処理中＋終わって間もないもの（バッジとモーダルの一覧）
  def index
    progresses = scope.recent.order(:id).to_a.each(&:fail_if_stale!)
    render json: { progresses: progresses.map(&:as_progress_json) }
  end

  def show
    progress = scope.find(params[:id])
    progress.fail_if_stale!
    render json: progress.as_progress_json
  end

  def cancel
    progress = scope.find(params[:id])
    progress.request_cancel!
    render json: progress.reload.as_progress_json
  end

  private
    def scope = JobProgress.where(user: current_user)
end
