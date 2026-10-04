module Authentication
  extend ActiveSupport::Concern

  included do
    before_action :require_authentication
    helper_method :authenticated?, :impersonating?
  end

  class_methods do
    def allow_unauthenticated_access(**options)
      skip_before_action :require_authentication, **options
    end
  end

  private
    def authenticated?
      resume_session
    end

    def require_authentication
      resume_session || request_authentication
    end

    def resume_session
      return if @impersonation_ended

      Current.session ||= find_session_by_cookie
    end

    def find_session_by_cookie
      return unless cookies.signed[:session_id]

      session = Session.active_user.find_by(id: cookies.signed[:session_id])
      return session unless session&.impersonating?
      return session if session.impersonation_valid?

      # 代理ログインの期限切れ（30分）、または管理者が無効になった：自動で終了し、Cookie を元の管理者に戻す。
      # このリクエスト自体は実行しない（対象ユーザーとして入力された内容を、管理者の権限で実行してしまわないため）。
      flash[:notice] = "代理ログインを終了しました（時間切れ）。"
      end_impersonation!(session, via: "expired")
      Current.session = nil
      @impersonation_ended = true
      nil
    end

    def impersonating?
      Current.session&.impersonating? || false
    end

    def request_authentication
      return redirect_to(admin_users_path, status: :see_other) if @impersonation_ended # 元の管理者に戻った（戻れなければ次のリクエストでログイン画面）

      session[:return_to_after_authenticating] = request.url
      redirect_to new_session_path
    end

    def after_authentication_url
      session.delete(:return_to_after_authenticating) || root_url
    end

    def start_new_session_for(user)
      user.sessions.create!(user_agent: request.user_agent, ip_address: request.remote_ip).tap do |session|
        Current.session = session
        set_session_cookie(session)
      end
    end

    def set_session_cookie(session)
      cookies.signed.permanent[:session_id] = { value: session.id, httponly: true, same_site: :lax }
    end

    # 管理者が target として操作する Session を作り、Cookie をそちらに切り替える。管理者本人の Session は残す（元に戻る用）
    def start_impersonation!(target, reason)
      admin_session = Current.session
      session = target.sessions.create!(
        user_agent: request.user_agent, ip_address: request.remote_ip,
        impersonator: admin_session.user, impersonation_reason: reason,
        impersonation_expires_at: Session::IMPERSONATION_LIMIT.from_now, origin_session_id: admin_session.id
      )
      AuditLog.record!(:impersonation_start, target, user: target, impersonator: admin_session.user,
                       metadata: { reason: reason, expires_at: session.impersonation_expires_at, session_id: session.id })
      Current.session = session
      set_session_cookie(session)
      session
    end

    # 代理ログインを終わらせ、元の管理者の Session に戻す（戻れなければログアウト扱い）。戻り先の Session か nil を返す
    def end_impersonation!(session, via:)
      AuditLog.record!(:impersonation_end, session.user, user: session.user, impersonator: session.impersonator,
                       metadata: { reason: session.impersonation_reason, via: via, session_id: session.id })
      origin = Session.active_user.find_by(id: session.origin_session_id, user_id: session.impersonator_id)
      session.destroy
      if origin
        Current.session = origin
        set_session_cookie(origin)
      else
        Current.session = nil
        cookies.delete(:session_id)
      end
      origin
    end

    # パスワード（と 2FA）を通ったあとの共通の仕上げ
    def complete_login!(user)
      user.register_successful_login!
      start_new_session_for user
      LoginEvent.record!(email_address: user.email_address, user: user, success: true, request: request)
      AuditLog.record!(:login, user, user: user)
    end

    def terminate_session
      Current.session.destroy
      cookies.delete(:session_id)
    end
end
