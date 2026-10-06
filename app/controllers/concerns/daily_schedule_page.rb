# 1日のスケジュール画面の共通部分（index と、入力エラーで画面を描き直す tasks コントローラ）
module DailySchedulePage
  extend ActiveSupport::Concern

  included { helper_method :daily_schedule_path_for }

  private
    def parse_date(value)
      Date.iso8601(value.to_s)
    rescue ArgumentError
      Time.zone.today
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
