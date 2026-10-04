# role ベースの権限チェック。viewer（閲覧のみ）< staff < system_admin
module Authorization
  extend ActiveSupport::Concern

  class NotAuthorized < StandardError; end

  included do
    before_action { Current.ip_address = request.remote_ip }
    before_action :forbid_viewer_writes
    rescue_from NotAuthorized, with: :render_forbidden
    helper_method :current_user
  end

  class_methods do
    # viewer でも許す書き込み（自分のログアウトなど）
    def allow_viewer_writes(**options)
      skip_before_action :forbid_viewer_writes, **options
    end
  end

  private
    def current_user
      Current.user
    end

    def require_system_admin!
      raise NotAuthorized unless current_user&.system_admin?
    end

    # viewer は作成・更新・削除（GET / HEAD 以外）をすべて 403 にする
    def forbid_viewer_writes
      return unless current_user&.viewer?
      return if request.get? || request.head?

      render plain: "この操作を行う権限がありません。", status: :forbidden
    end

    def render_forbidden
      respond_to do |format|
        format.html { redirect_back_or_to root_path, alert: "この操作を行う権限がありません。" }
        format.any { head :forbidden }
      end
    end
end
