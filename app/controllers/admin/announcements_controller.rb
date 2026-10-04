module Admin
  class AnnouncementsController < BaseController
    before_action :set_announcement, only: %i[ edit update destroy ]

    def index
      @announcements = Announcement.order(starts_at: :desc)
    end

    def new
      @announcement = Announcement.new(starts_at: Time.current.beginning_of_hour, ends_at: 1.week.from_now.beginning_of_hour)
    end

    def create
      @announcement = Announcement.new(announcement_params.merge(created_by: current_user))
      if @announcement.save
        AuditLog.record!(:create, @announcement, metadata: { title: @announcement.title })
        redirect_to admin_announcements_path, notice: "お知らせを作成しました。"
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
    end

    def update
      if @announcement.update(announcement_params)
        AuditLog.record!(:update, @announcement, metadata: { title: @announcement.title })
        redirect_to admin_announcements_path, notice: "お知らせを更新しました。"
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      AuditLog.record!(:delete, @announcement, metadata: { title: @announcement.title })
      @announcement.destroy!
      redirect_to admin_announcements_path, notice: "お知らせを削除しました。", status: :see_other
    end

    private
      def set_announcement
        @announcement = Announcement.find(params[:id])
      end

      def announcement_params
        params.expect(announcement: %i[ title body starts_at ends_at ])
      end
  end
end
