# 自分のログイン中の端末（sessions）の一覧と切断
class UserSessionsController < ApplicationController
  allow_viewer_writes # 自分のセッションの切断は viewer にも許す

  def index
    @sessions = current_user.sessions.order(created_at: :desc)
  end

  def destroy
    target = current_user.sessions.find(params[:id])
    AuditLog.record!(:revoke_session, current_user, metadata: { session_id: target.id, ip_address: target.ip_address, user_agent: target.user_agent })
    if target == Current.session
      terminate_session
      redirect_to new_session_path, status: :see_other
    else
      target.destroy!
      redirect_to user_sessions_path, notice: "端末を切断しました。", status: :see_other
    end
  end

  def destroy_others
    others = current_user.sessions.where.not(id: Current.session.id)
    count = others.count
    others.destroy_all
    AuditLog.record!(:revoke_session, current_user, metadata: { scope: "others", count: count })
    redirect_to user_sessions_path, notice: "ほかの端末をすべて切断しました（#{count}件）。", status: :see_other
  end
end
