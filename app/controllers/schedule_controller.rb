# schedule-web（Cloudflare Pages の静的サイト）を、juku-desk のサイドバーを残したまま本文に埋め込む。
# ログインが必要な範囲は他の画面と同じ（Authentication の既定）。
class ScheduleController < ApplicationController
  PATHS = { index: "/", admin: "/admin", pickup: "/pickup" }.freeze

  PATHS.each_key do |page|
    define_method(page) do
      @schedule_src = schedule_src(PATHS.fetch(page))
      attach_token if @schedule_src
    end
  end

  private
    # SUPABASE_JWT_SECRET があるときだけ、短命の JWT を URL のフラグメント（#token=）で iframe に渡す。
    # フラグメントはサーバーにもログにも送られない。期限前の差し替えは postMessage（schedule_token_controller.js）。
    def attach_token
      result = SupabaseToken.issue(current_user) or return
      @schedule_token = result
      @schedule_origin = URI.parse(@schedule_src).then { |u| "#{u.scheme}://#{u.host}#{":#{u.port}" unless u.port == u.default_port}" }
      @schedule_src = "#{@schedule_src}#token=#{result.token}"
      response.headers["Cache-Control"] = "no-store" # トークン入りの HTML をキャッシュさせない
    end

    # http(s) の URL だけ受け付ける。未設定・不正なら nil（画面には「未設定」と出す）
    def schedule_src(path)
      value = ENV["SCHEDULE_WEB_URL"].to_s.strip
      uri = URI.parse(value)
      "#{value.delete_suffix("/")}#{path}" if uri.is_a?(URI::HTTP) && uri.host.present?
    rescue URI::InvalidURIError
      nil
    end
end
