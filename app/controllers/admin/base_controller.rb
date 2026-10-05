module Admin
  # 管理画面はすべて system_admin 専用
  class BaseController < ApplicationController
    before_action :require_system_admin!
  end
end
