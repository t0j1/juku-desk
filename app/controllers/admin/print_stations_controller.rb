module Admin
  # 教室PCの自動印刷エージェントの登録と、トークンの失効・再発行。トークンは発行した直後の画面で 1 度だけ見せる。
  class PrintStationsController < BaseController
    before_action :set_station, only: %i[ revoke reissue test_print test_result ]

    def index
      @stations = PrintStation.order(:name)
    end

    def new
      @station = PrintStation.new
    end

    def create
      @station, @token = PrintStation.register!(name: params.expect(print_station: [ :name ])[:name], created_by: current_user)
      AuditLog.record!(:print_station_register, @station, metadata: { name: @station.name })
      render :token
    rescue ActiveRecord::RecordInvalid => e
      @station = e.record
      render :new, status: :unprocessable_entity
    end

    def revoke
      @station.revoke!
      AuditLog.record!(:print_station_revoke, @station, metadata: { name: @station.name })
      redirect_to admin_print_stations_path, notice: "「#{@station.name}」のトークンを失効しました。", status: :see_other
    end

    def reissue
      @token = @station.reissue_token!
      AuditLog.record!(:print_station_reissue, @station, metadata: { name: @station.name })
      render :token
    end

    # サンプルを刷るジョブを作る。刷れたら、トレイ・両面・ホチキスの結果を test_result で入力する
    def test_print
      attrs = params.fetch(:test_print, {}).permit(:driver_preset, :staple)
      job = @station.start_test_print!(created_by: current_user, **attrs.to_h.symbolize_keys)
      AuditLog.record!(:print_station_test_print, @station, metadata: { name: @station.name, job_id: job.id })
      redirect_to admin_print_stations_path, notice: "「#{@station.name}」にテスト印刷のジョブを作りました。刷れたら、結果を入力してください。", status: :see_other
    rescue ArgumentError, ActiveRecord::RecordInvalid => e
      redirect_to admin_print_stations_path, alert: e.message, status: :see_other
    end

    def test_result
      @station.record_test_result!(params.fetch(:result, {}).permit(*PrintStation::TEST_FIELDS))
      AuditLog.record!(:print_station_test_result, @station, metadata: { name: @station.name, result: @station.test_print_result.except("answered_at") })
      redirect_to admin_print_stations_path, notice: "「#{@station.name}」のテスト印刷の結果を保存しました。", status: :see_other
    rescue ArgumentError => e
      redirect_to admin_print_stations_path, alert: e.message, status: :see_other
    end

    private
      def set_station
        @station = PrintStation.find(params[:id])
      end
  end
end
