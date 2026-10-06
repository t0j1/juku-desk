# 1日のスケジュール画面の共通部分（index と、入力エラーで画面を描き直す tasks コントローラ）
module DailySchedulePage
  extend ActiveSupport::Concern

  class InvalidDate < StandardError; end

  included do
    helper_method :daily_schedule_path_for
    rescue_from(InvalidDate) { redirect_to daily_schedule_path, alert: "日付の形式が正しくありません（例：2026-10-05）。今日の画面に戻しました。", status: :see_other }
  end

  private
    # 空なら今日。形式が不正な日付は今日に丸めず、InvalidDate にする（画面側で知らせる）
    def parse_date(value)
      return Time.zone.today if value.blank?

      Date.iso8601(value.to_s)
    rescue ArgumentError
      raise InvalidDate
    end

    def daily_schedule_path_for(date, **extra)
      daily_schedule_path(extra.merge(date: (date == Time.zone.today ? nil : date.iso8601)).compact)
    end

    def load_day(date, selected_id: nil)
      @date = date
      @tasks = DailyScheduleTask.for_date(date)
      @selected = @tasks.find { |t| t.id == selected_id.to_i } || @tasks.first
      @executions = DailyScheduleExecution.where(scheduled_at: date.beginning_of_day..date.end_of_day,
                                                 daily_schedule_task_id: @tasks.map(&:id)).index_by(&:daily_schedule_task_id)
      @stations = PrintStation.active.order(:name)
    end
end
