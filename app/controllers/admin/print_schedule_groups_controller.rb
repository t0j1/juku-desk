module Admin
  # 定例印刷のセット（同じ時刻から、中の雛形を順番に間隔を空けて刷る）。雛形をセットに入れるのは雛形の編集画面。ここでは作成・編集・停止・順番の変更。
  class PrintScheduleGroupsController < BaseController
    before_action :set_group, only: %i[ edit update destroy toggle move ]
    before_action :load_stations, only: %i[ new create edit update ]

    def new
      @group = PrintScheduleGroup.new(start_time: "08:00", interval_minutes: 2, weekdays: [ 1, 2, 3, 4, 5 ])
    end

    def create
      @group = PrintScheduleGroup.new(group_params.merge(created_by: current_user, print_station: @stations.find_by(id: params.dig(:print_schedule_group, :print_station_id))))
      @group.save!
      AuditLog.record!(:print_schedule_group_create, @group, metadata: { name: @group.name })
      redirect_to edit_admin_print_schedule_group_path(@group), notice: "セット「#{@group.name}」を作りました。雛形の編集画面で、このセットに入れてください。", status: :see_other
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound => e
      @error = e.respond_to?(:record) ? e.record.errors.full_messages.to_sentence : "ステーションを選んでください。"
      render :new, status: :unprocessable_entity
    end

    def edit
    end

    def update
      station = @stations.find_by(id: params.dig(:print_schedule_group, :print_station_id)) || @group.print_station
      @group.update!(group_params.merge(print_station: station))
      AuditLog.record!(:print_schedule_group_update, @group, metadata: { name: @group.name })
      redirect_to admin_print_schedules_path, notice: "セット「#{@group.name}」を更新しました。", status: :see_other
    rescue ActiveRecord::RecordInvalid => e
      @error = e.record.errors.full_messages.to_sentence
      render :edit, status: :unprocessable_entity
    end

    def toggle
      @group.update!(active: !@group.active)
      AuditLog.record!(:print_schedule_group_update, @group, metadata: { name: @group.name, active: @group.active })
      redirect_to admin_print_schedules_path, notice: "セット「#{@group.name}」を#{@group.active ? "有効" : "停止"}にしました。", status: :see_other
    end

    def move
      schedule = @group.print_schedules.find(params[:schedule_id])
      @group.move!(schedule, params[:direction])
      redirect_to edit_admin_print_schedule_group_path(@group), status: :see_other
    end

    def destroy
      @group.destroy!
      AuditLog.record!(:print_schedule_group_delete, @group, metadata: { name: @group.name })
      redirect_to admin_print_schedules_path, notice: "セット「#{@group.name}」を削除しました（中の雛形は残り、セット無しになります）。", status: :see_other
    end

    private
      def set_group = @group = PrintScheduleGroup.find(params[:id])

      def load_stations = @stations = PrintStation.active.order(:name)

      def group_params
        params.fetch(:print_schedule_group, {}).permit(:name, :start_time, :interval_minutes, :active, weekdays: [])
      end
  end
end
