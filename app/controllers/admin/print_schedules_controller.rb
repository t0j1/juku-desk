module Admin
  # 定例印刷の雛形（曜日と時刻に、翌日分の印刷ジョブを自動で作る）。作る側は PrintScheduleJob。
  class PrintSchedulesController < BaseController
    include DriverPresetHandling
    before_action :set_schedule, only: %i[ edit update destroy toggle ]

    def index
      @schedules = PrintSchedule.includes(:print_station).order(:id)
    end

    def new
      @schedule = PrintSchedule.new(copies: 1, collate: true, time_of_day: "08:00", weekdays: [ 1, 2, 3, 4, 5 ])
      load_choices
    end

    def create
      load_choices
      upload = params.dig(:print_schedule, :pdf)

      driver_preset, error = resolve_driver_preset(:print_schedule)
      if error
        return render_new(error)
      end

      new_preset = process_new_preset_if_any(:print_schedule)
      driver_preset = new_preset if new_preset

      attrs = schedule_params.to_h.symbolize_keys.compact_blank
      attrs[:driver_preset] = driver_preset.presence
      attrs[:print_station] = @stations.find_by(id: attrs.delete(:print_station_id))
      attrs.merge!(config_attrs(attrs[:kind]))
      @schedule = PrintSchedule.new(attrs)
      return render_new("ステーションを選んでください。") unless attrs[:print_station]
      return render_new("PDF ファイルを選んでください。") if @schedule.fixed_pdf? && !upload

      @schedule = if @schedule.fixed_pdf?
        PrintSchedule.create_with_pdf!(data: upload.read(PrintJob::MAX_PDF_BYTES + 1), created_by: current_user, **attrs)
      else
        PrintSchedule.create!(created_by: current_user, **attrs)
      end
      AuditLog.record!(:print_schedule_create, @schedule, metadata: audit_metadata(@schedule))
      redirect_to admin_print_schedules_path, notice: "「#{@schedule.name}」を登録しました。毎日 18:00 に、翌日の分のジョブを作ります。", status: :see_other
    rescue ActiveRecord::RecordInvalid => e
      render_new(e.record.errors.full_messages.to_sentence)
    rescue ArgumentError => e
      render_new(e.message)
    end

    def edit
    end

    # 固定PDFは、PDF を選べば差し替わる。種別は変えられる（変えると不要な PDF は手放す）。ステーションは有効なものから選び直せる
    def update
      attrs = schedule_params.to_h.symbolize_keys
      attrs[:weekdays] = Array(attrs[:weekdays]).compact_blank # 全部外したら空にして、検証で止める
      station = PrintStation.active.find_by(id: attrs.delete(:print_station_id)) || @schedule.print_station

      driver_preset, error = resolve_driver_preset(:print_schedule)
      if error
        @schedule.discard_uploaded_pdf
        @error = error
        return render :edit, status: :unprocessable_entity
      end

      new_preset = process_new_preset_if_any(:print_schedule)
      driver_preset = new_preset if new_preset

      attrs.merge!(config_attrs(attrs[:kind] || @schedule.kind))
      attrs[:driver_preset] = driver_preset.presence
      @schedule.assign_attributes(attrs.merge(print_station: station))
      upload = params.dig(:print_schedule, :pdf)
      @schedule.attach_pdf(upload.read(PrintJob::MAX_PDF_BYTES + 1)) if upload.respond_to?(:read) && @schedule.fixed_pdf?
      @schedule.save!
      AuditLog.record!(:print_schedule_update, @schedule, metadata: audit_metadata(@schedule).merge(active: @schedule.active))
      redirect_to admin_print_schedules_path, notice: "「#{@schedule.name}」を更新しました。次の生成（18:00）から反映されます。", status: :see_other
    rescue ActiveRecord::RecordInvalid, ArgumentError => e
      @schedule.discard_uploaded_pdf
      @error = e.respond_to?(:record) ? e.record.errors.full_messages.to_sentence : e.message
      render :edit, status: :unprocessable_entity
    end

    # 保存せずに、サンプルデータ（実在の生徒・単語帳は使わない）で 1 枚のプレビュー PDF を返す
    def preview
      kind = params.dig(:print_schedule, :kind).to_s
      return head :unprocessable_entity unless PrintSchedule.kinds.key?(kind) && kind != "fixed_pdf"

      schedule = PrintSchedule.new(kind: kind, **config_attrs(kind))
      _, layout_errors = PrintSchedule::Layout.resolve(kind, schedule.layout_config)
      return render plain: layout_errors.to_sentence, status: :unprocessable_entity if layout_errors.any?

      Tempfile.create([ "preview-", ".pdf" ]) do |file|
        schedule.build_document(Time.zone.today, sample: true).render_to(file.path)
        send_data File.binread(file.path), type: "application/pdf", disposition: "inline", filename: "preview.pdf"
      end
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
        load_choices if action_name.in?(%w[ edit update ])
      end

      def render_new(message)
        @error = message
        load_choices
        render :new, status: :unprocessable_entity
      end

      def schedule_params
        params.fetch(:print_schedule, {}).permit(:name, :kind, :print_station_id, :copies, :copies_mode, :collate, :staple, :time_of_day, :active, weekdays: [])
      end

      # 種別に合わせた source_config / layout_config（固定PDFは持たない）
      def config_attrs(kind)
        raw = params.fetch(:print_schedule, {})
        case kind.to_s
        when "roster"
          source = raw[:roster_source]&.permit(:target, :order, :attendance_box, :note_box, grades: [], student_ids: [])
          { source_config: PrintSchedule::RosterPdf.config_from_params(source), layout_config: layout_config_for("roster", raw), copies_mode: raw[:copies_mode].presence || "fixed" }
        when "word_test"
          source = raw[:word_test_source]&.permit(:wordbook_id, :start_no, :span, :direction, :question_mode, :count, :answers)
          { source_config: PrintSchedule::WordTestPdf.config_from_params(source), layout_config: layout_config_for("word_test", raw), copies_mode: "fixed" }
        else
          { source_config: {}, layout_config: {}, copies_mode: "fixed" }
        end
      end

      def layout_config_for(kind, raw)
        PrintSchedule::Layout.normalize(kind, raw[:layout]&.permit(*PrintSchedule::Layout.spec_for(kind).keys))
      end

      def load_choices
        @stations = PrintStation.active.order(:name)
        @wordbooks = Wordbook.order(:name)
        @grades = Student.enrolled.where.not(grade: [ nil, "" ]).distinct.pluck(:grade).sort_by { |g| PrintSchedule::Document::GRADE_ORDER.index(g) || 99 }
        @students = Student.enrolled.order(:name).pluck(:name, :id)
      end

      def audit_metadata(schedule)
        { name: schedule.name, kind: schedule.kind, station: schedule.print_station.name, weekdays: schedule.weekdays, time: schedule.time_of_day }
      end
  end
end