module Admin
  # 定例印刷の雛形（曜日と時刻に、翌日分の印刷ジョブを自動で作る）。作る側は PrintScheduleJob。
  class PrintSchedulesController < BaseController
    before_action :set_schedule, only: %i[ edit update destroy toggle ]

    def index
      @schedules = PrintSchedule.includes(:print_station).order(:id)
    end

    def new
      @schedule = PrintSchedule.new(copies: 1, collate: true, time_of_day: "08:00", weekdays: [ 1, 2, 3, 4, 5 ])
      @stations = PrintStation.active.order(:name)
    end

    def create
      @stations = PrintStation.active.order(:name)
      upload = params.dig(:print_schedule, :pdf)
      attrs = schedule_params.to_h.symbolize_keys.compact_blank
      attrs[:print_station] = @stations.find_by(id: attrs.delete(:print_station_id))
      @schedule = PrintSchedule.new(attrs)
      return render_new("PDF ファイルを選んでください。") unless upload
      return render_new("ステーションを選んでください。") unless attrs[:print_station]

      @schedule = PrintSchedule.create_with_pdf!(data: upload.read(PrintJob::MAX_PDF_BYTES + 1), created_by: current_user, **attrs)
      AuditLog.record!(:print_schedule_create, @schedule, metadata: { name: @schedule.name, station: @schedule.print_station.name, weekdays: @schedule.weekdays, time: @schedule.time_of_day })
      redirect_to admin_print_schedules_path, notice: "「#{@schedule.name}」を登録しました。毎日 18:00 に、翌日の分のジョブを作ります。", status: :see_other
    rescue ActiveRecord::RecordInvalid => e
      render_new(e.record.errors.full_messages.to_sentence)
    rescue ArgumentError => e
      render_new(e.message)
    end

    def edit
    end

    # PDF は差し替えない（差し替えたいときは、削除して登録し直す）。ステーションは有効なものから選び直せる
    def update
      attrs = schedule_params.to_h.symbolize_keys
      attrs[:weekdays] = Array(attrs[:weekdays]).compact_blank # 全部外したら空にして、検証で止める
      station = PrintStation.active.find_by(id: attrs.delete(:print_station_id)) || @schedule.print_station
      @schedule.assign_attributes(attrs.merge(print_station: station))
      @schedule.save!
      AuditLog.record!(:print_schedule_update, @schedule, metadata: { name: @schedule.name, station: station.name, weekdays: @schedule.weekdays, time: @schedule.time_of_day, active: @schedule.active })
      redirect_to admin_print_schedules_path, notice: "「#{@schedule.name}」を更新しました。次の生成（18:00）から反映されます。", status: :see_other
    rescue ActiveRecord::RecordInvalid => e
      @error = e.record.errors.full_messages.to_sentence
      render :edit, status: :unprocessable_entity
    end

    def toggle
      @schedule.update!(active: !@schedule.active)
      AuditLog.record!(:print_schedule_update, @schedule, metadata: { name: @schedule.name, active: @schedule.active })
      redirect_to admin_print_schedules_path, notice: "「#{@schedule.name}」を#{@schedule.active ? "有効" : "停止"}にしました。", status: :see_other
    end

    def destroy
      @schedule.destroy!
      AuditLog.record!(:print_schedule_delete, @schedule, metadata: { name: @schedule.name })
      redirect_to admin_print_schedules_path, notice: "「#{@schedule.name}」を削除しました（作成済みのジョブは残ります）。", status: :see_other
    end

    private
      def set_schedule
        @schedule = PrintSchedule.find(params[:id])
        @stations = PrintStation.active.order(:name) if action_name.in?(%w[ edit update ])
      end

      def render_new(message)
        @error = message
        render :new, status: :unprocessable_entity
      end

      def schedule_params
        params.fetch(:print_schedule, {}).permit(:name, :print_station_id, :copies, :collate, :staple, :driver_preset, :time_of_day, :active, weekdays: [])
      end
  end
end
