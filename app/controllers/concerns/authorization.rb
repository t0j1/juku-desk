# role ベースの権限チェック。instructor < manager < admin
module Authorization
  extend ActiveSupport::Concern

  class NotAuthorized < StandardError; end

  included do
    before_action { Current.ip_address = request.remote_ip }
    rescue_from NotAuthorized, with: :render_forbidden
    helper_method :current_user
  end

  private
    def current_user
      Current.user
    end

    def require_manager!
      raise NotAuthorized unless current_user&.manager_or_above?
    end

    def require_admin!
      raise NotAuthorized unless current_user&.admin?
    end

    def render_forbidden
      respond_to do |format|
        format.html { redirect_back_or_to root_path, alert: "この操作を行う権限がありません。" }
        format.any { head :forbidden }
      end
    end
end
