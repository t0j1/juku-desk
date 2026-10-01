# Phase 2 で lessons#index に置き換えるまでの仮トップ
class HomeController < ApplicationController
  def index
    redirect_to students_path
  end
end
