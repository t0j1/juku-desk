# 代理ログインを終えて、元の管理者に戻る（「元に戻る」ボタン）。どの権限のユーザーとして操作中でも使える。
class ImpersonationsController < ApplicationController
  allow_viewer_writes
  allow_without_two_factor

  def destroy
    return redirect_to root_path unless impersonating?

    name = Current.user.name
    end_impersonation!(Current.session, via: "manual")
    if Current.session
      redirect_to admin_users_path, notice: "#{name} としての代理ログインを終了しました。", status: :see_other
    else
      redirect_to new_session_path, status: :see_other
    end
  end
end
