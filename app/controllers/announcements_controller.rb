# 利用者が「既読にして閉じる」を押したときの記録。
class AnnouncementsController < ApplicationController
  allow_viewer_writes # 既読は自分の表示設定で、viewer にも許す

  def read
    announcement = Announcement.find(params[:id])
    AnnouncementRead.find_or_create_by!(announcement: announcement, user: current_user)
    redirect_back_or_to root_path, status: :see_other
  rescue ActiveRecord::RecordNotUnique
    redirect_back_or_to root_path, status: :see_other
  end
end
