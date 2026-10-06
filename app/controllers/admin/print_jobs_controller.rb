module Admin
  # 印刷ジョブの一覧と作成。通知は管理画面だけ（失敗・期限切れ・オフラインは一覧の上に出す）。
  class PrintJobsController < BaseController
    include DriverPresetHandling
    before_action :set_job, only: %i[ cancel print_now ]

    # 一覧の絞り込み。problems=1（失敗＋期限切れ）は既存の赤バナーからのリンク用に残す
    FILTERS = {
      "failed" => "失敗ジョブ",
      "expired" => "期限切れ",
      "overdue" => "未印刷（予定超過）",
      "heartbeat_lost" => "ハートビート途絶"
    }.freeze

    def index
      @only_problems = params[:problems].present?
      @filter = params[:filter].presence
      @filter = nil unless FILTERS.key?(@filter)
      @filters = FILTERS
      @jobs = filtered_jobs.limit(100)
      @problems = PrintJob.where(status: %i[ failed expired ], finished_at: 1.day.ago..).count
      @offline_stations = PrintStation.active.reject(&:online?)
      @waiting = PrintJob.overdue_pending.count
      @filter_counts = {
        failed: PrintJob.failed.count,
        expired: PrintJob.expired.count,
        overdue: @waiting,
        heartbeat_lost: PrintJob.on_lost_stations.count
      }
    end

    def new
      load_choices
      @job = PrintJob.new(scheduled_at: Time.current, copies: 1, collate: true)
    end

    def create
      load_choices
      upload = params.dig(:print_job, :pdf)
      output = @outputs.find { |o| o.id == params.dig(:print_job, :output_id).to_i } unless upload
      station = PrintStation.active.find_by(id: params.dig(:print_job, :print_station_id))
      title = upload ? File.basename(upload.original_filename.to_s, ".*").presence : output&.display_name

      driver_preset, error = resolve_driver_preset(:print_job)
      if error
        return render_new(error)
      end

      new_preset = process_new_preset_if_any(:print_job)
      driver_preset = new_preset if new_preset

      attrs = job_params.to_h.symbolize_keys.compact_blank
      attrs[:driver_preset] = driver_preset.presence
      @job = PrintJob.new(attrs.merge(print_station: station, title: title))
      return render_new("印刷する PDF を選ぶか、PDF ファイルをアップロードしてください。") unless upload || output
      return render_new("ステーションを選んでください。") unless station

      if upload
        @job = PrintJob.create_with_pdf!(data: upload.read(PrintJob::MAX_PDF_BYTES + 1), station: station, title: title, created_by: current_user, **attrs)
      else
        PdfSplitter::Builder.with_file(output) do |path|
          @job = PrintJob.create_with_pdf!(path: path, station: station, title: title, created_by: current_user, **attrs)
        end
      end
      AuditLog.record!(:create, @job, metadata: { title: @job.title, station: station.name, copies: @job.copies })
      redirect_to admin_print_jobs_path, notice: "「#{@job.title}」の印刷ジョブを作りました。", status: :see_other
    rescue ActiveRecord::RecordInvalid => e
      render_new(e.record.errors.full_messages.to_sentence)
    rescue ArgumentError => e
      render_new(e.message)
    end

    def cancel
      if @job.cancel!
        AuditLog.record!(:update, @job, metadata: { title: @job.title, action: "cancel" })
        redirect_to admin_print_jobs_path, notice: "「#{@job.title}」を取り消しました。", status: :see_other
      else
        redirect_to admin_print_jobs_path, alert: "このジョブはすでに終わっています。", status: :see_other
      end
    end

    # 待っているジョブを、予定時刻を待たずに今すぐ刷る対象にする（次のポーリングで取りに行く）
    def print_now
      unless @job.pending?
        return redirect_to admin_print_jobs_path, alert: "待機中のジョブだけ「今すぐ印刷」できます。", status: :see_other
      end

      @job.update!(scheduled_at: Time.current, expires_at: [ @job.expires_at, Time.current + PrintJob::DEFAULT_DEADLINE ].max)
      AuditLog.record!(:update, @job, metadata: { title: @job.title, action: "print_now" })
      redirect_to admin_print_jobs_path, notice: "「#{@job.title}」を今すぐ印刷の対象にしました。", status: :see_other
    end

    private
      def set_job
        @job = PrintJob.find(params[:id])
      end

      # 絞り込みの適用。filter が無ければ problems=1 のときだけ失敗・期限切れに絞る（既存の挙動）
      def filtered_jobs
        base = PrintJob.includes(:print_station).order(id: :desc)
        case @filter
        when "failed" then base.failed
        when "expired" then base.expired
        when "overdue" then base.overdue_pending
        when "heartbeat_lost" then base.on_lost_stations
        else @only_problems ? base.where(status: %i[ failed expired ]) : base
        end
      end

      def load_choices
        @stations = PrintStation.active.order(:name)
        @outputs = PdfSplitOutput.joins(:pdf_split_job).where(pdf_split_jobs: { user_id: current_user.id }).order(id: :desc).limit(200).to_a
      end

      def render_new(message)
        @job ||= PrintJob.new
        @error = message
        render :new, status: :unprocessable_entity
      end

      def job_params
        params.fetch(:print_job, {}).permit(:scheduled_at, :expires_at, :copies, :collate, :staple, :duplex)
      end
  end
end