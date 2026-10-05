module Admin
  # 教室PCの自動印刷エージェントの登録と、トークンの失効・再発行。トークンは発行した直後の画面で 1 度だけ見せる。
  class PrintStationsController < BaseController
    before_action :set_station, only: %i[ revoke reissue ]

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

    private
      def set_station
        @station = PrintStation.find(params[:id])
      end
  end
end
