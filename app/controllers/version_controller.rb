# GET /up/version: デプロイ済みのコミットSHAと起動時刻だけを返す（認証なし）。SHA以外の情報は出さない
class VersionController < ActionController::Base
  BOOTED_AT = Time.current.utc.iso8601

  def show
    render json: { sha: ENV.fetch("RENDER_GIT_COMMIT", nil).presence || "unknown", booted_at: BOOTED_AT }
  end
end
