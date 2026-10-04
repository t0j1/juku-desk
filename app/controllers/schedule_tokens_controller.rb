# iframe（schedule-web）に渡すトークンの再発行。期限前に画面側から呼ぶ（schedule_token_controller.js）。
# ログアウト・セッション切断・ユーザー停止のあとは 401（Authentication が Session を引けなくなる）。
class ScheduleTokensController < ApplicationController
  skip_before_action :require_authentication
  allow_viewer_writes # トークン発行は書き込みではない（viewer もスケジュールを見る）

  def create
    return head :unauthorized unless authenticated?
    return head :forbidden if impersonating?

    result = SupabaseToken.issue(current_user)
    return head :no_content unless result # SUPABASE_JWT_SECRET 未設定

    response.headers["Cache-Control"] = "no-store"
    render json: { token: result.token, exp: result.expires_at }
  end
end
